module App (mkApp, mkWaiApp, genBlocks) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad (when)
import Data.Either (fromRight)
import Data.Monoid ((<>))
import Data.Text.Encoding (decodeUtf8)
import Control.Concurrent.Chan
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as Char8
import qualified Data.Text as T
import qualified Data.Text.Lazy as LT

import Network.Wai (Application)
import Web.Scotty
import Data.Aeson (Value(..), toJSON, object, (.=))
import System.FilePath (combine)
import System.Posix.Files (getFileStatus, fileSize)
import qualified Database.Redis as R
import qualified Data.HashMap.Strict as M

import Type
import Config
import RD.Lib (sha1sum)

genBlocks :: Integer -> Integer -> [Block]
genBlocks fileSize blockSize = if fileSize == 0 then
                                   []
                               else
                                   go (0 :: Integer) (0 :: Integer) []
  where
    go :: Integer -> Integer -> [Block] -> [Block]
    go blockId startByte accumulator
      | fileSize - startByte == blockSize =
        reverse ((blockId, startByte, fileSize - 1) : accumulator)
      | fileSize - startByte > blockSize =
        go (blockId + 1) (startByte + blockSize)
          ((blockId, startByte, startByte + blockSize - 1) : accumulator)
      | startByte < fileSize =
        reverse ((blockId, startByte, fileSize - 1) : accumulator)
      | otherwise = reverse accumulator

-- | fill block sha1sum, if sha1sum is not ready yet, put "pending" there.
fillSha1sum :: RDRuntimeConfig -> FillBlockParam -> IO [BlockWithChecksum]
fillSha1sum runtimeConfig fbp = do
  let filepath = fbpFilepath fbp
      blockSize = fbpBlockSize fbp
      hashKey = blockSha1sumHashKey fbp
  redisReply <- R.runRedis (redisConn runtimeConfig) $ R.hgetall hashKey
  case redisReply of
    Left reply -> do
      putStrLn $ "redis hgetall " <> show hashKey <> " failed: " <> show reply
      return $ map fillBlock (fbpBlocks fbp) where
        fillBlock (blockId, start, end) = (blockId, start, end, "pending")
    Right blockIdSha1sumAlist -> do
      putStrLn $ "redis hgetall " <> show hashKey <> " ok"
      return $ map fillBlock (fbpBlocks fbp) where
        blockIdSha1sumMap = M.fromList blockIdSha1sumAlist
        fillBlock :: Block -> BlockWithChecksum
        fillBlock (blockId, start, end) = (blockId, start, end, decodeUtf8 $ M.lookupDefault "pending" (blockIdKey blockId) blockIdSha1sumMap)

-- | given a redis connection pool, return a Scotty app.
mkApp :: RDRuntimeConfig -> ScottyM ()
mkApp runtimeConfig = do
  get (literal "/rd/") $ json $
      object ["ok" .= True
             ,"app" .= ("reliable-download api" :: T.Text)]
  get (regex "^/rd/(.*)") $ do
    path :: LT.Text <- param "1"
    let filepath = combine (webRoot (config runtimeConfig)) (LT.unpack path)
    liftIO $ putStrLn $ "get block metadata for " <> filepath
    fileStatus <- liftIO $ getFileStatus filepath    -- TODO catch IO exception
    let fileSizeInByte = toInteger $ fileSize fileStatus
        blockSizeInByte = 2097152    -- 2MiB
        blockCount = (fileSizeInByte - 1) `div` blockSizeInByte + 1
        blocks = genBlocks fileSizeInByte blockSizeInByte
        fbp = FillBlockParam { fbpFilepath=filepath
                             , fbpFileSize=fileSizeInByte
                             , fbpBlockSize=blockSizeInByte
                             , fbpBlocks=blocks }
        strKey = fileStatusKey fbp
        jsonRespFileStatusCheckFailed = json $
          object ["ok" .= False
                 ,"path" .= path
                 ,"filepath" .= filepath
                 ,"msg" .= ("check file status in redis failed" :: T.Text)]
        jsonRespOk = do
          blocksWithSha1sum <- liftIO $ fillSha1sum runtimeConfig fbp
          json $ object ["ok" .= True
                        ,"block_size" .= ("2MiB" :: T.Text)
                        ,"file_size" .= fileSizeInByte
                        ,"block_count" .= blockCount
                        ,"blocks" .= blocksWithSha1sum
                        ,"path" .= path
                        ,"filepath" .= filepath]

    -- if this file is new or has status "error", add task to fileChan.
    redisReply <- liftIO $ R.runRedis (redisConn runtimeConfig) $ R.setnx strKey "working"
    statusCheckResult <- case redisReply of
      Left reply -> do
        liftIO $ putStrLn $ "redis setnx " <> show strKey <> " failed: " <> show reply
        return False
      Right setNxResult ->
        if setNxResult then do
            liftIO $ writeChan (fileChan runtimeConfig) fbp
            return True
        else do
            liftIO $ putStrLn $ "redis key " <> show strKey <> " exists. file is old"
            -- if status is error, set it to working, then add task to fileChan
            redisReply2 <- liftIO $ R.runRedis (redisConn runtimeConfig) $ R.get strKey
            case redisReply2 of
              Left reply -> do
                liftIO $ putStrLn $ "redis file status check for " <> show strKey <> " failed: " <> show reply
                return False
              Right statusStr ->
                liftIO $ if statusStr == Just "error"
                  then do
                    putStrLn $ "set file status to \"working\" for " <> show strKey
                    redisReply3 <- liftIO $ R.runRedis (redisConn runtimeConfig) $ R.set strKey "working"
                    case redisReply3 of
                      Left reply -> do
                        liftIO $ putStrLn $ "set file status to \"working\" failed: " <> show reply
                        return False
                      Right _ -> do
                        liftIO $ writeChan (fileChan runtimeConfig) fbp
                        return True
                  else return True
    if statusCheckResult then
        jsonRespOk
    else
        jsonRespFileStatusCheckFailed

  get (regex "^/test/rd/(.*)") $ do  -- for testing path capture
    path :: LT.Text <- param "1"
    let filepath = combine (webRoot (config runtimeConfig)) (LT.unpack path)
    json $ object ["ok" .= True
                  ,"path" .= path
                  ,"filepath" .= filepath]
  get "/debug/t1" $ do
    sha1 <- liftIO $ sha1sum "/home/sylecn/persist/cache/ideaIC-2018.1.tar.gz"
    json $ object ["ok" .= True
                  ,"sha1sum" .= sha1]
  get "/debug/count" $ do
    count <- liftIO $ R.runRedis (redisConn runtimeConfig) $ R.incr "count"
    json $ object ["ok" .= True
                  ,"count" .= fromRight 0 count]

-- | given a redis connection pool, return a WAI app.
mkWaiApp :: RDRuntimeConfig -> IO Application
mkWaiApp = scottyApp . mkApp

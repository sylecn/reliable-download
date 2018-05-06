module App (mkApp, mkWaiApp, genBlocks) where

import Control.Monad.IO.Class (liftIO)
import Data.Either (fromRight)
import Data.Monoid ((<>))
import Data.Text.Encoding (decodeUtf8)
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

import Config
import RD.Lib (sha1sum)

type BlockID = Integer
type Block = (BlockID, Integer, Integer)
type BlockWithChecksum = (BlockID, Integer, Integer, T.Text)

genBlocks :: Integer -> Integer -> [Block]
genBlocks fileSize blockSize = if fileSize == 0 then
                                   []
                               else
                                   go (0 :: Integer) (0 :: Integer) []
  where
    go :: Integer -> Integer -> [Block] -> [Block]
    go blockId startByte accumulator =
        if fileSize - startByte == blockSize then
            reverse ((blockId, startByte, fileSize - 1):accumulator)
        else if fileSize - startByte > blockSize then
            go (blockId + 1)
               (startByte + blockSize)
               ((blockId, startByte, startByte + blockSize - 1):accumulator)
        else if startByte < fileSize then
            reverse ((blockId, startByte, fileSize - 1):accumulator)
        else
            reverse accumulator

data FillBlockParam = FillBlockParam {
      fbpFilepath :: FilePath
    , fbpBlockSize :: Integer
    , fbpFileSize :: Integer
    , fbpBlocks :: [Block]}

-- | the redis hash key used to store cached sha1sum for given FillBlockParam
blockSha1sumHashKey :: FillBlockParam -> B.ByteString
blockSha1sumHashKey fbp = Char8.pack (fbpFilepath fbp) <> "_" <> (Char8.pack . show) (fbpBlockSize fbp)

-- | the redis hash key sub key, used to store the sha1sum for that blockId.
blockIdKey :: BlockID -> B.ByteString
blockIdKey = Char8.pack . show

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
  get (literal "/rd/") $ do
    json $ object [("ok" .= True)
                  ,("app" .= ("reliable-download api" :: T.Text))]
  get (regex "^/rd/(.*)") $ do
    path :: LT.Text <- param "1"
    let filepath = combine (webRoot (config runtimeConfig)) (LT.unpack path)
    liftIO $ putStrLn $ "get block metadata for " <> filepath
    fileStatus <- liftIO $ getFileStatus filepath    -- TODO catch IO exception
    let fileSizeInByte = toInteger $ fileSize fileStatus
        blockSizeInByte = 2097152    -- 2MiB
        blockCount = (fileSizeInByte - 1) `div` blockSizeInByte + 1
        blocks = genBlocks fileSizeInByte blockSizeInByte
    blocksWithSha1sum <- liftIO $ fillSha1sum runtimeConfig $ FillBlockParam {
                              fbpFilepath=filepath
                            , fbpFileSize=fileSizeInByte
                            , fbpBlockSize=blockSizeInByte
                            , fbpBlocks=blocks}
    json $ object [("ok" .= True)
                  ,("block_size" .= ("2MiB" :: T.Text))
                  ,("file_size" .= fileSizeInByte)
                  ,("block_count" .= blockCount)
                  ,("blocks" .= blocksWithSha1sum)
                  ,("path" .= path)
                  ,("filepath" .= filepath)
                  ]
  get (regex "^/test/rd/(.*)") $ do  -- for testing path capture
    path :: LT.Text <- param "1"
    let filepath = combine (webRoot (config runtimeConfig)) (LT.unpack path)
    json $ object [("ok" .= True)
                  ,("path" .= path)
                  ,("filepath" .= filepath)
                  ]
  get "/debug/t1" $ do
    sha1 <- liftIO $ sha1sum "/home/sylecn/persist/cache/ideaIC-2018.1.tar.gz"
    json $ object ["ok" .= True
                  ,"sha1sum" .= sha1]
  get "/debug/count" $ do
    count <- liftIO $ R.runRedis (redisConn runtimeConfig) $ do
                        count <- R.incr "count"
                        return count
    json $ object ["ok" .= True
                  ,"count" .= fromRight 0 count]

-- | given a redis connection pool, return a WAI app.
mkWaiApp :: RDRuntimeConfig -> IO Application
mkWaiApp = scottyApp . mkApp

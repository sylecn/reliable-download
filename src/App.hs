module App (mkApp, mkWaiApp) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Class (lift)
import Data.Either (fromRight)
import Data.Either.Extra (fromRight')
import Data.Monoid ((<>))
import Data.Text.Encoding (decodeUtf8)
import Control.Concurrent.Chan
import System.IO.Error (catchIOError)
import Control.Monad (when)
import qualified Data.Text as T
import qualified Data.Text.Lazy as LT

import Network.Wai (Application)
import Web.Scotty
import Data.Aeson (object, (.=))
import System.FilePath ((</>))
import System.Posix.Files (getFileStatus, fileSize)
import Control.Error
import qualified Database.Redis as R
import qualified Data.HashMap.Strict as M

import Type
import Config
import Lib (sha1sum, genBlocks)
import Utils
import qualified DB

-- | fill block sha1sum, if sha1sum is not ready yet, put "pending" there.
fillSha1sum :: RDRuntimeConfig -> FillBlockParam -> IO [BlockWithChecksum]
fillSha1sum rc fbp = do
  let hashKey = blockSha1sumHashKey fbp
  redisReply <- R.runRedis (rcRedisConn rc) $ R.hgetall hashKey
  case redisReply of
    Left reply -> do
      logl rc $ "redis hgetall " <> showt hashKey <> " failed: " <> showt reply
      return $ map fillBlock (fbpBlocks fbp) where
        fillBlock (blockId, start, end) = (blockId, start, end, "pending")
    Right blockIdSha1sumAlist -> do
      logl rc $ "fillSha1sum: redis hgetall " <> showt hashKey <> " ok"
      return $ map fillBlock (fbpBlocks fbp) where
        blockIdSha1sumMap = M.fromList blockIdSha1sumAlist
        fillBlock :: Block -> BlockWithChecksum
        fillBlock (blockId, start, end) = (blockId, start, end, decodeUtf8 $ M.lookupDefault "pending" (blockIdKey blockId) blockIdSha1sumMap)

-- | given a FillBlockParam, if this file is new, send job to worker and mark
-- it as working. if there is an error, return IO Left.
processNewFileAsyncMaybe :: RDRuntimeConfig -> FillBlockParam -> ExceptT T.Text IO ()
processNewFileAsyncMaybe rc fbp = do
  let strKey = fileStatusKey fbp
  resultE <- liftIO $ DB.insertIfNotExist rc strKey fileStatusWorking
  throwOnLeft resultE
  let insertOk = fromRight' resultE
  if insertOk then liftIO $ do
      logl rc $ showt strKey <> " is a new file, sending task to worker"
      writeChan (rcFileChan rc) fbp
      return ()
  else do
    oldStatusE <- liftIO $ do
      logl rc $ showt strKey <> " is not a new file"
      -- if status is error, set it to working, then add task to fileChan
      DB.get rc strKey
    throwOnLeftMsg oldStatusE "get old file status failed"
    let oldStatus = fromRight' oldStatusE
    when (oldStatus == Just fileStatusError) $ do
        setResultE <- liftIO $ do
          logl rc $ showt strKey <> " was in " <> showt fileStatusError <> " status"
          DB.set rc strKey fileStatusWorking
        throwOnLeftMsg setResultE $ "set file status to " <> showt fileStatusWorking <> " failed"
        liftIO $ writeChan (rcFileChan rc) fbp

-- | GET /rd/.* handler
getRdHandler :: RDRuntimeConfig -> ExceptT T.Text ActionM ()
getRdHandler rc = do
  path <- lift $ param "1"

  let filepath = webRoot (rcConfig rc) </> T.unpack path
  fileStatusE <- lift $ do
    liftIO $ logl rc $ "user request " <> showt filepath
    liftIO $ catchIOError
      (fmap Right (getFileStatus filepath))
      (\e -> do
         let msg = "getFileStatus on " <> T.pack filepath <> " failed"
         logl rc $ msg <> ":\n\t" <> T.pack (show e)
         return $ Left msg)
  throwOnLeft fileStatusE
  let fileStatus = fromRight' fileStatusE

  lift $ do
    let fileSizeInByte = toInteger $ fileSize fileStatus
        blockSizeInByte = 2097152    -- 2MiB
        blockCount = (fileSizeInByte - 1) `div` blockSizeInByte + 1
        blocks = genBlocks fileSizeInByte blockSizeInByte
        fbp = FillBlockParam { fbpFilepath=filepath
                             , fbpFileSize=fileSizeInByte
                             , fbpBlockSize=blockSizeInByte
                             , fbpBlocks=blocks }
    resultE <- liftIO $ runExceptT $ processNewFileAsyncMaybe rc fbp
    case resultE of
      Left msg -> json $
          object ["ok" .= False
                 ,"path" .= path
                 ,"filepath" .= filepath
                 ,"msg" .= msg]
      Right _ -> do
          blocksWithSha1sum <- liftIO $ fillSha1sum rc fbp
          json RDResponse { respOk=True
                          , respMsg=""
                          , respPath=path
                          , respFilePath=filepath
                          , respBlockSize="2MiB"
                          , respFileSize=fileSizeInByte
                          , respBlockCount=blockCount
                          , respBlocks=blocksWithSha1sum }

-- | given a redis connection pool, return a Scotty app.
mkApp :: RDRuntimeConfig -> ScottyM ()
mkApp rc = do
  get (literal "/rd/") $ json $
      object ["ok" .= True
             ,"app" .= ("reliable-download api" :: T.Text)]

  get (regex "^/rd/(.*)") $ do
    result <- runExceptT $ getRdHandler rc
    case result of
      Left msg -> json rdErrorResponse { respMsg=msg }
      Right resp -> return resp

  get (regex "^/test/rd/(.*)") $ do  -- for testing path capture
    path :: LT.Text <- param "1"
    let filepath = webRoot (rcConfig rc) </> LT.unpack path
    json $ object ["ok" .= True
                  ,"path" .= path
                  ,"filepath" .= filepath]

  get "/debug/t1" $ do
    sha1 <- liftIO $ sha1sum "/home/sylecn/persist/cache/ideaIC-2018.1.tar.gz"
    json $ object ["ok" .= True
                  ,"sha1sum" .= sha1]

  get "/debug/count" $ do
    count <- liftIO $ R.runRedis (rcRedisConn rc) $ R.incr "count"
    json $ object ["ok" .= True
                  ,"count" .= fromRight 0 count]

-- | given a redis connection pool, return a WAI app.
mkWaiApp :: RDRuntimeConfig -> IO Application
mkWaiApp = scottyApp . mkApp

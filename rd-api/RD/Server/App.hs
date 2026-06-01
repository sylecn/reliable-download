module RD.Server.App (mkApp, mkWaiApp) where

import Control.Monad.Trans.Class (lift)
import Data.Either (fromRight)
import Data.Either.Extra (fromRight')
import Control.Concurrent.Chan
import System.IO.Error (catchIOError)
import Control.Monad (unless)
import qualified Data.Text as T
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as LB

import Network.Wai (Application, pathInfo)
import Web.Scotty
import Data.Aeson (object, (.=))
import System.FilePath ((</>))
import System.Directory (makeAbsolute)
import System.Posix.Files (getFileStatus, fileSize)
import Control.Error
import qualified Database.Redis as R
import qualified Data.HashMap.Strict as M

import RD.CliVersion (cliVersion)
import RD.Types
import RD.Server.Config
import RD.Lib (sha1sum, sha1sumOnBytes, genBlocks)
import RD.Utils
import qualified RD.Server.DB as DB

blockSizeText :: Integer -> T.Text
blockSizeText sizeInByte =
  if sizeInByte `mod` (1024 * 1024) == 0
    then showt (sizeInByte `div` (1024 * 1024)) <> "MiB"
    else showt sizeInByte <> "B"

-- | fill block sha1sum, if sha1sum is not ready yet, put "pending" there.
fillSha1sum :: RDRuntimeConfig -> FillBlockParam -> IO [BlockWithChecksum]
fillSha1sum rc fbp = do
  let hashKey = blockSha1sumHashKey fbp
  redisReply <- R.runRedis (rcRedisConn rc) $ R.hgetall hashKey
  case redisReply of
    Left reply -> do
      errorl rc $ "redis hgetall " <> decodeUtf8 hashKey <> " failed: " <> showt reply
      return $ map fillBlock (fbpBlocks fbp) where
        fillBlock (blockId, start, end) = (blockId, start, end, "pending")
    Right blockIdSha1sumAlist -> do
      debugl rc $ "fillSha1sum: redis hgetall " <> decodeUtf8 hashKey <> " ok"
      return $ map fillBlock (fbpBlocks fbp) where
        blockIdSha1sumMap = M.fromList blockIdSha1sumAlist
        fillBlock :: Block -> BlockWithChecksum
        fillBlock (blockId, start, end) = (blockId, start, end, decodeUtf8 $ M.lookupDefault "pending" (blockIdKey blockId) blockIdSha1sumMap)

-- | a sha1sum that has different types, used for storing sha1sum in redis.
-- only used in isNewFile.
sha1sumByteString :: FilePath -> IO B.ByteString
sha1sumByteString filename = do
  bytes <- LB.readFile filename
  return $ B.toStrict $ sha1sumOnBytes bytes

-- | invalidate all redis keys for a file, including all block-size variants.
invalidateFileCaches :: RDRuntimeConfig -> FilePath -> IO (Either T.Text ())
invalidateFileCaches rc filename = do
  let keyPattern = encodeUtf8 $ T.pack filename <> "_*"
  redisReply <- R.runRedis (rcRedisConn rc) $ R.keys keyPattern
  case redisReply of
    Left reply -> do
      let msg = "redis keys " <> decodeUtf8 keyPattern <> " failed: " <> showt reply
      errorl rc msg
      return $ Left msg
    Right keys -> do
      if null keys then
        return $ Right ()
      else do
        delReply <- R.runRedis (rcRedisConn rc) $ R.del keys
        case delReply of
          Left reply -> do
            let msg = "redis del " <> decodeUtf8 keyPattern <> " failed: " <> showt reply
            errorl rc msg
            return $ Left msg
          Right deletedCount ->
            do
              debugl rc $ "invalidated " <> showt deletedCount <> " redis keys for " <> T.pack filename
              return $ Right ()

-- | try set file's working status to FileStatusWorking if it has not been set before.
trySetFileToWorkingStatus :: RDRuntimeConfig -> B.ByteString -> IO (Either T.Text Bool)
trySetFileToWorkingStatus rc strKey = do
  DB.insertIfNotExist rc strKey $ fsBytes FileStatusWorking

-- | return True if given file and block size is a new combination. if file
-- content has changed, it is always considered a new file, old cache will be
-- purged. when this function return Right True, it will set working flag in
-- redis for the file name and block size combination.
isNewFile :: RDRuntimeConfig -> FillBlockParam -> IO (Either T.Text Bool)
isNewFile rc fbp = do
  let strKey = fileStatusKey fbp
      fn = T.pack $ fbpFilepath fbp
  -- units -o %15f --terse 100MiB byte
  if fbpFileSize fbp < 104857600 then do
    cachedSha1E <- DB.get rc (fileSha1Key fbp)
    case cachedSha1E of
      Left msg -> return $ Left msg
      Right sha1Maybe -> do
        currentSha1 <- sha1sumByteString $ fbpFilepath fbp
        case sha1Maybe of
          Just cachedSha1 -> do
            if currentSha1 /= cachedSha1
              then do
                -- set progress to working
                warnl rc $ "file sha1 changed, will recalculate block hashes: " <> fn
                invalidateE <- invalidateFileCaches rc (fbpFilepath fbp)
                case invalidateE of
                  Left msg -> return $ Left msg
                  Right _ -> do
                    infol rc $ "invalidated cached keys for " <> fn
                    _ <- DB.set rc (fileSha1Key fbp) currentSha1
                    resultE <- DB.set rc strKey $ fsBytes FileStatusWorking
                    case resultE of
                      Left _ -> return $ Left "set file status to working failed"
                      Right _ -> return $ Right True
              else do
                debugl rc $ "file sha1 not changed: " <> fn
                trySetFileToWorkingStatus rc strKey
          Nothing -> do
            resultE <- DB.set rc (fileSha1Key fbp) currentSha1
            case resultE of
              Left msg -> return $ Left msg
              Right _ -> trySetFileToWorkingStatus rc strKey
  else do
    debugl rc "file sha1 is not checked for large files"
    trySetFileToWorkingStatus rc strKey

-- | given a FillBlockParam, if this file is new, send job to worker and mark
-- it as working. if there is an error, return IO Left.
processNewFileAsyncMaybe :: RDRuntimeConfig -> FillBlockParam -> ExceptT T.Text IO ()
processNewFileAsyncMaybe rc fbp = do
  let strKey = fileStatusKey fbp
      filePath = fbpFilepath fbp
  resultE <- liftIO $ isNewFile rc fbp
  throwOnLeft resultE
  let insertOk = fromRight' resultE
  if insertOk then liftIO $ do
    infol rc $ T.pack filePath <> " is a new file, sending task to worker"
    writeChan (rcFileChan rc) fbp
    return ()
  else do
    oldStatusE <- liftIO $ do
      debugl rc $ T.pack filePath <> " is not a new file"
      -- if status is error, set it to working, then add task to fileChan
      DB.get rc strKey
    throwOnLeftMsg oldStatusE "get old file status failed"
    let oldStatus = fromRight' oldStatusE
    case fmap fsFromBytes oldStatus of
      Just FileStatusError -> do
        setResultE <- liftIO $ do
          infol rc $ "file status was " <> showt FileStatusError <> ", retry now"
          DB.set rc strKey $ fsBytes FileStatusWorking
        throwOnLeftMsg setResultE $ "set file status to " <> showt FileStatusWorking <> " failed"
        liftIO $ writeChan (rcFileChan rc) fbp
      Just FileStatusDone -> liftIO $ debugl rc $ "file status is " <> showt FileStatusDone
      Just FileStatusWorking -> liftIO $ debugl rc $ "file status is " <> showt FileStatusWorking
      _ -> liftIO $ errorl rc "Unexpected file status"

-- | GET /rd/.* handler
getRdHandler :: RDRuntimeConfig -> ExceptT T.Text ActionM ()
getRdHandler rc = do
  unless (rcHasRedis rc) $
      throwE "No redis on server side, rd client support is disabled"
  req <- lift request
  let relFilePath = T.intercalate "/" $ drop 1 $ pathInfo req
      filepath = webRoot (rcConfig rc) </> T.unpack relFilePath
  absFilePath <- liftIO $ makeAbsolute $ T.unpack relFilePath
  fileStatusE <- lift $ do
    liftIO $ infol rc $ "user request rd metadata for " <> relFilePath
    liftIO $ catchIOError
      (fmap Right (getFileStatus $ T.unpack relFilePath))
      (\e -> do
         let msg = "getFileStatus on " <> relFilePath <> " failed"
         errorl rc $ msg <> ":\n\t" <> T.pack (show e)
         return $ Left msg)
  throwOnLeft fileStatusE
  let fileStatus = fromRight' fileStatusE

  lift $ do
    let fileSizeInByte = toInteger $ fileSize fileStatus
        bsInByte = blockSizeInByte (rcConfig rc)
        blockCount = (fileSizeInByte - 1) `div` bsInByte + 1
        blocks = genBlocks fileSizeInByte bsInByte
        fbp = FillBlockParam { fbpFilepath=absFilePath
                             , fbpFileSize=fileSizeInByte
                             , fbpBlockSize=bsInByte
                             , fbpBlocks=blocks }
    resultE <- liftIO $ runExceptT $ processNewFileAsyncMaybe rc fbp
    case resultE of
      Left msg -> json $
          object ["ok" .= False
                 ,"path" .= relFilePath
                 ,"filepath" .= filepath
                 ,"msg" .= msg]
      Right _ -> do
          blocksWithSha1sum <- liftIO $ fillSha1sum rc fbp
          json RDResponse { respOk=True
                          , respMsg=""
                          , respPath=relFilePath
                          , respFilePath=filepath
                          , respBlockSize=blockSizeText bsInByte
                          , respFileSize=fileSizeInByte
                          , respBlockCount=blockCount
                          , respBlocks=blocksWithSha1sum }

-- | given a redis connection pool, return a Scotty app.
mkApp :: RDRuntimeConfig -> ScottyM ()
mkApp rc = do
  get (literal "/rd/") $ json $
      object ["ok" .= True
             ,"app" .= ("reliable-download api" :: T.Text)
             ,"version" .= T.pack cliVersion]

  get (regex "^/rd/") $ do
    result <- runExceptT $ getRdHandler rc
    case result of
      Left msg -> json rdErrorResponse { respMsg=msg }
      Right resp -> return resp

  get (regex "^/test-rd/") $ do    -- for testing path capture
    req <- request
    let fullPath = "/" <> T.intercalate "/" (pathInfo req)
        relFilePath = T.intercalate "/" $ drop 1 $ pathInfo req
    let filepath = webRoot (rcConfig rc) </> T.unpack relFilePath
    json $ object ["ok" .= True
                  ,"path" .= relFilePath -- file path in URL
                  ,"filepath" .= filepath -- file path on server side
                  ,"fullPath" .= fullPath] -- HTTP request path

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

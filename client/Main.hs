module Main (main) where

import Options.Applicative
import Data.Semigroup ((<>))
import Data.Maybe (isJust, fromMaybe)
import Control.Monad (when, unless, forM_, mzero)
import System.Directory ( createDirectoryIfMissing
                        , doesFileExist
                        , removeDirectoryRecursive
                        , removeFile)
import Control.Exception
import System.IO.Error
import System.Exit
import System.FilePath ((</>))
import Data.Text.Encoding (decodeUtf8)
import Control.Concurrent (threadDelay)
import Control.Monad.Trans.Maybe
import Control.Monad.IO.Class (liftIO)
import System.Socket (SocketException)

import qualified Data.Text as T
import qualified Data.ByteString.Lazy as LB
import qualified Data.ByteString.Char8 as Char8

import Network.HTTP.Types (statusCode)
import Network.HTTP.Simple
import Network.HTTP.Client (path, responseStatus)
import Formatting hiding (bytes)
import Control.Retry (retrying, constantDelay, limitRetries, rsIterNumber)
import qualified System.Logger as L

import Lib (sha1sumOnBytes, guessFilename)
import Utils
import Type
import Opts
import Task

-- | log a msg using given log level
clientLogl :: L.Level -> RDClientRuntimeConfig -> T.Text -> IO ()
clientLogl level rc msg = do
  let logger = rdLogger rc
  L.log logger level $ L.msg msg
  L.flush logger

-- | log a debug msg
debugl :: RDClientRuntimeConfig -> T.Text -> IO ()
debugl = clientLogl L.Debug

-- | log an info msg
infol :: RDClientRuntimeConfig -> T.Text -> IO ()
infol = clientLogl L.Info

-- | log an warn msg
warnl :: RDClientRuntimeConfig -> T.Text -> IO ()
warnl = clientLogl L.Warn

-- | log an error msg
errorl :: RDClientRuntimeConfig -> T.Text -> IO ()
errorl = clientLogl L.Error

-- | convert byte number to MiB. small number will become 0.
humanReadableSize :: Integer -> String
humanReadableSize bytes = show (bytes `div` 1048576) <> " MiB"

-- | best padding for this many blocks
bestPadding :: Integer -> Int
bestPadding = length . show

data FetchBlockParam = FetchBlockParam {
      fbpUrl :: T.Text
    , fbpFilename :: FilePath
    , fbpBlockWithChecksum :: BlockWithChecksum
    , fbpBlockTargetFile :: FilePath }

-- | Run an action and recover from a raised exception by potentially retrying
-- the action a number of times. see Control.Retry.recovering for more info.
-- delay is in microseconds.
--
-- this function only capture HttpException in action op.
retryOnFailure :: RDClientRuntimeConfig -> Int -> Int -> IO Bool -> IO Bool
retryOnFailure rc times delay op = retrying policy checker wrappedAction where
  policy = constantDelay delay <> limitRetries times
  checker _rs = return . not
  wrappedAction rs = do
    when (rsIterNumber rs > 0)
         (errorl rc $ "retrying for the " <> showt (rsIterNumber rs) <> " time")
    op `catches` [Handler (\ (e :: HttpException) -> do
                             errorl rc $ "got HttpException: " <> showt e
                             return False)
                 ,Handler (\ (e :: IOException) -> do
                             errorl rc $ "got IOException: " <> showt e
                             return False)
                 ,Handler (\ (e :: SocketException) -> do
                             errorl rc $ "got SocketException: " <> showt e
                             return False)]

-- | try fetch block data from http, if fetched data matches sha1sum, write it
-- to blockTargetFile and return IO True. Otherwise, return IO False.
fetchBlockFromHttp :: RDClientRuntimeConfig -> FetchBlockParam -> IO Bool
fetchBlockFromHttp rc fbp = do
  let (blockId, start, end, sha1sum) = fbpBlockWithChecksum fbp
      filename = fbpFilename fbp
      rangeHeader = "bytes=" <> Char8.pack (show start) <> "-"
                             <> Char8.pack (show end)
  assert (sha1sum /= "pending") (return ())
  debugl rc $ "downloading " <> showt filename <> " block " <> showt blockId
  req <- parseRequest $ T.unpack $ fbpUrl fbp
  response <- httpLBS $ addRequestHeader "Range" rangeHeader req
  let statuscode = statusCode $ responseStatus response
  -- for small files, range may cover all bytes, result status is 200.
  if statuscode `notElem` [206, 200] then do
      errorl rc $ "get block " <> showt blockId <> " failed, HTTP status code is " <> showt statuscode
      return False
  else do
      let bodyLBS = getResponseBody response
      if (decodeUtf8 . LB.toStrict . sha1sumOnBytes) bodyLBS == sha1sum then do
          let blockTargetFile = fbpBlockTargetFile fbp
          debugl rc $ "writing block data to " <> showt blockTargetFile
          LB.writeFile blockTargetFile bodyLBS
          infol rc $ "block " <> showt blockId <> " fetched"
          return True
      else do
          errorl rc $ "sha1sum verification failed for " <> showt filename <> " block " <> showt blockId <> ", expect " <> showt sha1sum
          return False

-- | return block target file name (just base filename, no dir info)
getBlockFilename :: RDResponse -> BlockWithChecksum -> FilePath
getBlockFilename rdResp blockWithChecksum =
  let padding = bestPadding $ respBlockCount rdResp
      (blockId, _, _, sha1sum) = blockWithChecksum in
  formatToString ("block" % left padding '0' % "_" % stext) blockId sha1sum

-- | fetch a single block, write block data to disk. return IO True on success
fetchBlock :: RDClientRuntimeConfig -> T.Text -> RDResponse -> BlockWithChecksum -> IO Bool
fetchBlock rc url rdResp blockWithChecksum = do
  let opts = rdOptions rc
      filename = guessFilename url
      blockFileDir = tempDir opts </> filename
      blockFilename = getBlockFilename rdResp blockWithChecksum
      blockTargetFile = blockFileDir </> blockFilename
  result <- catchIOError
            (do
              createDirectoryIfMissing True blockFileDir
              return True)
            (\e -> do
               errorl rc $ "Create temp dir " <> showt blockFileDir <> " failed: " <> showt e
               return False)
  if not result then
      return False
  else do
    fileExist <- doesFileExist blockTargetFile
    if fileExist then
        return True
    else
        retryOnFailure rc (blockMaxRetry opts) 1000000 $ fetchBlockFromHttp rc (FetchBlockParam url filename blockWithChecksum blockTargetFile)

-- | return block target file names in correct order.
getBlockTargetFilenames :: RDOptions -> RDResponse -> [FilePath]
getBlockTargetFilenames opts rdResp =
  let blockFileDir = tempDir opts </> guessFilename (respPath rdResp)
      getBlockTargetFile blockWithChecksum = blockFileDir </> getBlockFilename rdResp blockWithChecksum in
  map getBlockTargetFile (respBlocks rdResp)

-- | return target file base filename and full name.
getTargetFilename :: RDOptions -> RDResponse -> (FilePath, FilePath)
getTargetFilename opts rdResp =
  let outDir = outputDir opts
      filename = guessFilename $ respPath rdResp
      targetFilename = outDir </> filename in
  (filename, targetFilename)

-- | combine downloaded blocks to the final file. let MaybeT finish with Just
-- on success.
combineBlocks :: RDClientRuntimeConfig -> RDResponse -> MaybeT IO ()
combineBlocks rc rdResp = do
  let opts = rdOptions rc
      (filename, targetFilename) = getTargetFilename opts rdResp
  fileExist <- liftIO $ doesFileExist targetFilename
  when (forceOverwrite opts && fileExist) $ do
      result <- liftIO $ catchIOError
        (do
          removeFile targetFilename
          return True)
        (\e -> do
           errorl rc $ "remove existing file failed: " <> showt e
           return False)
      unless result mzero
  liftIO $ do
    infol rc $ "combining blocks to create " <> showt targetFilename
    forM_ (getBlockTargetFilenames opts rdResp) $ \blockFilename -> do
      debugl rc $ "appending block file " <> showt blockFilename
      content <- LB.readFile blockFilename
      LB.appendFile targetFilename content  -- TODO how to handle error here?
                                            -- let it crash?
    infol rc $ "file downloaded to " <> showt targetFilename
    unless (keepBlockData opts) $ do
      let tempdir = tempDir opts </> filename
      debugl rc $ "delete temporary block data dir " <> showt tempdir
      catchIOError (removeDirectoryRecursive tempdir)
                   (\e -> warnl rc $ "Warning: delete temp block data dir failed: " <> showt e)

-- | call /rd/<file> api and fetch response
getRDResponse :: RDClientRuntimeConfig -> T.Text -> IO RDResponse
getRDResponse rc url = catches
  (do
    req <- parseRequest $ T.unpack url
    resp <- httpJSON $ req { path="/rd" <> path req }
    return $ getResponseBody resp)
   [Handler (\ (e :: HttpException) -> do
               errorl rc $ "getRDResponse HttpException: " <> showt e
               return $ rdErrorResponse {
                            respOk=False
                          , respMsg="got HttpException " <> T.pack (show e)})
   ,Handler (\ (e :: JSONException) -> do
               errorl rc $ "getRDResponse JSONException: " <> showt e
               return $ rdErrorResponse {
                            respOk=False
                          , respMsg="json decode failed: " <> T.pack (show e)})]

-- | download file at given URL using reliable download API and block based
-- downloading.
downloadFile :: RDClientRuntimeConfig -> T.Text -> MaybeT IO Bool
downloadFile rc url = do
  let opts = rdOptions rc
  downloadTask <- liftIO $ newTask $ workerCount opts
  rdResp <- liftIO $ getRDResponse rc url
  unless (respOk rdResp) $ do
    liftIO $ errorl rc $ "GET /rd/ api failed: " <> showt (respMsg rdResp)
    mzero
  liftIO $ infol rc "GET /rd/ api ok"
  let (_filename, targetFilename) = getTargetFilename opts rdResp
  fileExist <- liftIO $ doesFileExist targetFilename
  when (fileExist && not (forceOverwrite opts)) $ do
    liftIO $ warnl rc $ "Warning: skip already existing file " <> showt targetFilename <> ", use -f to force overwrite"
    mzero
  liftIO $ do
    infol rc $ "Downloading file: " <> respPath rdResp <> ", "
             <> T.pack (humanReadableSize (respFileSize rdResp))
             <> ", " <> showt (respBlockCount rdResp) <> " blocks"
    rdResp2 <- loopUntilAllBlocksReady rc url rdResp [] downloadTask
    results <- getTaskResults downloadTask
    if and results then do
      resultMaybe <- runMaybeT $ combineBlocks rc rdResp2
      return $ isJust resultMaybe
    else do
      errorl rc $ (showt . length . filter id) results <> " blocks failed."
      return False

-- | a sleep loop that check whether all blocks in rdResp is ready, if not, do
-- a GET again later and check it again. On each try, the diff of new ready
-- blocks are sent to fetchBlock function.
--
-- block download is managed by downloadTask :: Task Bool.
-- to supports concurrent download.
--
-- Return last RDResponse when all blocks are ready and sent to downloadTask.
loopUntilAllBlocksReady :: RDClientRuntimeConfig -> T.Text -> RDResponse -> [BlockID] -> Task Bool -> IO RDResponse
loopUntilAllBlocksReady rc url rdResp oldReadyBlocks downloadTask = do
  let blockIsReady = (/= "pending") . getBlockSha1sum
      blocks = respBlocks rdResp
      readyBlocks = filter blockIsReady blocks
      newReadyBlocks = filter ((`notElem` oldReadyBlocks) . getBlockId) readyBlocks
      allBlocksReady = all blockIsReady blocks
  infol rc $ (showt . length) newReadyBlocks <> " new block(s) ready on server side"
  addTasks downloadTask $ map (fetchBlock rc url rdResp) newReadyBlocks
  if allBlocksReady then
    -- loop finished
    return rdResp
  else do
    when (null newReadyBlocks) $ do
         infol rc "No new blocks ready on server side, waiting 1s"
         threadDelay 1000000
    newRdResp <- getRDResponse rc url
    unless (respOk newRdResp) $
         errorl rc $ "getRDResponse failed: " <> respMsg newRdResp
    let prevResp = if respOk newRdResp then newRdResp else rdResp
    loopUntilAllBlocksReady rc url prevResp (map getBlockId readyBlocks) downloadTask

cliApp :: RDOptions -> IO ()
cliApp opts = do
  let level = if verbose opts then L.Debug else L.Info
      -- Note: tinylog doesn't support non-GMT dateformat.
      logSettings = (L.setFormat (Just "%0H:%0M:%0S") .
                     L.setLogLevel level .
                     L.setDelimiter "  ")
                    L.defSettings
  logger <- L.new logSettings
  let rc = RDClientRuntimeConfig { rdOptions=opts
                                 , rdLogger=logger}
  debugl rc $ "command line options: " <> showt opts
  let dir = tempDir opts
  catchIOError (createDirectoryIfMissing True dir)
               (\e -> do
                  errorl rc $ "Create temp dir " <> showt dir <> " failed: " <> showt e
                  exitFailure)
  debugl rc $ "using temp dir: " <> showt dir
  -- resultsMaybe :: [Maybe Bool]
  resultsMaybe <- mapM (runMaybeT . downloadFile rc) (urls opts)
  let results = map (fromMaybe False) resultsMaybe
  if and results then
      infol rc "all urls downloaded."
  else do
      errorl rc $ (showt . length . filter not) results <> " urls failed/skipped."
      exitFailure

main :: IO ()
main = do
  opts <- execParser parserInfo
  if showVersion opts then
      putStrLn "rd 1.0.0.0"
  else
    if null $ urls opts then do
      putStrLn "No URLs given, nothing to do. See rd --help"
      exitFailure
    else
      cliApp opts
  where
    parserInfo = info (argParser <**> helper)
      (  fullDesc
      <> header "rd - reliable download command line tool"
      <> progDesc "Download large files across slow and unstable network reliably. Requires using rd-api on server side. For more information, see rd-api --help")

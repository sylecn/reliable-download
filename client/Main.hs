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
import Control.Concurrent.QSem
import Control.Concurrent.Async (async, wait)
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

import RD.Lib (sha1sumOnBytes, guessFilename)
import Type
import Opts

debug :: RDOptions -> String -> IO ()
debug opts msg = when (verbose opts) $ putStrLn msg

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
retryOnFailure :: Int -> Int -> IO Bool -> IO Bool
retryOnFailure times delay op = retrying policy checker wrappedAction where
  policy = constantDelay delay <> limitRetries times
  checker _rs = return . not
  wrappedAction rs = do
    when (rsIterNumber rs > 0)
         (putStrLn $ "retrying for the " <> show (rsIterNumber rs) <> " time")
    op `catches` [Handler (\ (e :: HttpException) -> do
                             print $ "got HttpException: " <> show e
                             return False)
                 ,Handler (\ (e :: IOException) -> do
                             print $ "got IOException: " <> show e
                             return False)
                 ,Handler (\ (e :: SocketException) -> do
                             print $ "got SocketException: " <> show e
                             return False)]

-- | try fetch block data from http, if fetched data matches sha1sum, write it
-- to blockTargetFile and return IO True. Otherwise, return IO False.
fetchBlockFromHttp :: RDOptions -> FetchBlockParam -> IO Bool
fetchBlockFromHttp opts fbp = do
  let (blockId, start, end, sha1sum) = fbpBlockWithChecksum fbp
      filename = fbpFilename fbp
      rangeHeader = "bytes=" <> Char8.pack (show start) <> "-"
                             <> Char8.pack (show end)
  assert (sha1sum /= "pending") (return ())
  debug opts $ "downloading " <> filename <> " block " <> show blockId
  req <- parseRequest $ T.unpack $ fbpUrl fbp
  response <- httpLBS $ addRequestHeader "Range" rangeHeader req
  let statuscode = statusCode $ responseStatus response
  if statuscode /= 206 then do
      putStrLn $ "get block " <> show blockId <> " failed, HTTP status code is " <> show statuscode
      return False
  else do
      let bodyLBS = getResponseBody response
      if (decodeUtf8 . LB.toStrict . sha1sumOnBytes) bodyLBS == sha1sum then do
          let blockTargetFile = fbpBlockTargetFile fbp
          debug opts $ "writing block data to " <> blockTargetFile
          LB.writeFile blockTargetFile bodyLBS
          putStrLn $ "block " <> show blockId <> " fetched"
          return True
      else do
          putStrLn $ "sha1sum verification failed for " <> filename <> " block " <> show blockId <> ", expect " <> show sha1sum
          return False

-- | return block target file name (just base filename, no dir info)
getBlockFilename :: RDResponse -> BlockWithChecksum -> FilePath
getBlockFilename rdResp blockWithChecksum =
  let padding = bestPadding $ respBlockCount rdResp
      (blockId, _, _, sha1sum) = blockWithChecksum in
  formatToString ("block" % left padding '0' % "_" % stext) blockId sha1sum

-- | fetch a single block, return IO True on success
fetchBlock :: RDOptions -> T.Text -> RDResponse -> BlockWithChecksum -> IO Bool
fetchBlock opts url rdResp blockWithChecksum = do
  let filename = guessFilename url
      blockFileDir = tempDir opts </> filename
      blockFilename = getBlockFilename rdResp blockWithChecksum
      blockTargetFile = blockFileDir </> blockFilename
  result <- catchIOError
            (do
              createDirectoryIfMissing True blockFileDir
              return True)
            (\e -> do
               putStrLn $ "Create temp dir " <> blockFileDir <> " failed: " <> show e
               return False)
  if not result then
      return False
  else do
    fileExist <- doesFileExist blockTargetFile
    if fileExist then
        return True
    else
        retryOnFailure (blockMaxRetry opts) 1000000 $ fetchBlockFromHttp opts (FetchBlockParam url filename blockWithChecksum blockTargetFile)

-- | fetch block asynchronously using a worker pool
fetchBlockAsync :: RDClientRuntimeConfig -> T.Text -> RDResponse -> BlockWithChecksum -> IO Bool
fetchBlockAsync rc url rdResp blockWithChecksum =
  bracket_
    (waitQSem $ workerSem rc)
    (signalQSem $ workerSem rc)
    $ do
      ar <- async $ fetchBlock (rdOptions rc) url rdResp blockWithChecksum
      wait ar

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
combineBlocks :: RDOptions -> RDResponse -> MaybeT IO ()
combineBlocks opts rdResp = do
  let (filename, targetFilename) = getTargetFilename opts rdResp
  fileExist <- liftIO $ doesFileExist targetFilename
  when (forceOverwrite opts && fileExist) $ do
      result <- liftIO $ catchIOError
        (do
          removeFile targetFilename
          return True)
        (\e -> do
           putStrLn $ "remove existing file failed: " <> show e
           return False)
      unless result mzero
  liftIO $ do
    putStrLn $ "combining blocks to create " <> targetFilename
    forM_ (getBlockTargetFilenames opts rdResp) $ \blockFilename -> do
      debug opts $ "appending block file " <> blockFilename
      content <- LB.readFile blockFilename
      LB.appendFile targetFilename content  -- TODO how to handle error here?
                                            -- let it crash?
    putStrLn $ "file downloaded to " <> targetFilename
    unless (keepBlockData opts) $ do
      let tempdir = tempDir opts </> filename
      debug opts $ "delete temporary block data dir " <> tempdir
      catchIOError (removeDirectoryRecursive tempdir)
                   (\e -> putStrLn $ "Warning: delete temp block data dir failed: " <> show e)

-- | call /rd/<file> api and fetch response
getRDResponse :: RDOptions -> T.Text -> IO RDResponse
getRDResponse _opts url = catches
  (do
    req <- parseRequest $ T.unpack url
    resp <- httpJSON $ req { path="/rd" <> path req }
    return $ getResponseBody resp)
   [Handler (\ (e :: HttpException) -> do
               putStrLn $ "getRDResponse HttpException: " <> show e
               return $ rdErrorResponse {
                            respOk=False
                          , respMsg="got HttpException " <> T.pack (show e)})
   ,Handler (\ (e :: JSONException) -> do
               putStrLn $ "getRDResponse JSONException: " <> show e
               return $ rdErrorResponse {
                            respOk=False
                          , respMsg="json decode failed: " <> T.pack (show e)})]

-- | download file at given URL using reliable download API and block based
-- downloading.
downloadFile :: RDClientRuntimeConfig -> T.Text -> MaybeT IO Bool
downloadFile rc url = do
  let opts = rdOptions rc
  rdResp <- liftIO $ getRDResponse opts url
  unless (respOk rdResp) $ do
    liftIO $ putStrLn $ "GET /rd/ api failed: " <> show (respMsg rdResp)
    mzero
  liftIO $ putStrLn "GET /rd/ api ok"
  let (_filename, targetFilename) = getTargetFilename opts rdResp
  fileExist <- liftIO $ doesFileExist targetFilename
  when (fileExist && not (forceOverwrite opts)) $ do
    liftIO $ putStrLn $ "Warning: skip already existing file " <> targetFilename <> ", use -f to force overwrite"
    mzero
  liftIO $ do
    putStrLn $ "Downloading file: " <> show (respPath rdResp) <> ", "
             <> humanReadableSize (respFileSize rdResp)
             <> ", " <> show (respBlockCount rdResp) <> " blocks"
    (rdResp2, results) <- loopUntilAllBlocksReady rc url rdResp []
    if and results then do
      resultMaybe <- runMaybeT $ combineBlocks opts rdResp2
      return $ isJust resultMaybe
    else do
      putStrLn $ (show . length . filter id) results <> " blocks failed."
      return False

-- | a sleep loop that check whether all blocks in rdResp is ready, if not, do
-- a GET again later and check it again. On each try, the diff of new ready
-- blocks are sent to fetchBlock function.
--
-- Return whether download is successful for each block.
loopUntilAllBlocksReady :: RDClientRuntimeConfig -> T.Text -> RDResponse -> [BlockID] -> IO (RDResponse, [Bool])
loopUntilAllBlocksReady rc url rdResp oldReadyBlocks = do
  let blockIsReady = (/= "pending") . getBlockSha1sum
      blocks = respBlocks rdResp
      readyBlocks = filter blockIsReady blocks
      newReadyBlocks = filter ((`notElem` oldReadyBlocks) . getBlockId) readyBlocks
      allBlocksReady = all blockIsReady blocks
  putStrLn $ (show . length) newReadyBlocks <> " new block(s) ready on server side"
  results <- mapM (fetchBlockAsync rc url rdResp) newReadyBlocks
  if allBlocksReady then
    -- loop finished
    return (rdResp, results)
  else do
    when (null newReadyBlocks) $ do
         putStrLn "No new blocks ready on server side, waiting 1s"
         threadDelay 1000000
    newRdResp <- getRDResponse (rdOptions rc) url
    unless (respOk newRdResp) $ do
         putStrLn $ "getRDResponse failed: " <> T.unpack (respMsg newRdResp)
    let prevResp = if respOk newRdResp then newRdResp else rdResp
    loopUntilAllBlocksReady rc url prevResp (map getBlockId readyBlocks)

cliApp :: RDOptions -> IO ()
cliApp opts = do
  debug opts $ "command line options: " <> show opts
  let dir = tempDir opts
  catchIOError (createDirectoryIfMissing True dir)
               (\e -> die $ "Create temp dir " <> dir <> " failed: " <> show e)
  debug opts $ "using temp dir: " <> dir
  sem <- newQSem $ workerCount opts
  let rc = RDClientRuntimeConfig { rdOptions=opts
                                 , workerSem=sem}
  -- resultsMaybe :: [Maybe Bool]
  resultsMaybe <- mapM (runMaybeT . downloadFile rc) (urls opts)
  let results = map (fromMaybe False) resultsMaybe
  if and results then
      putStrLn "all urls downloaded."
  else
      die $ (show . length . filter not) results <> " urls failed/skipped."

main :: IO ()
main = cliApp =<< execParser opts
  where
    opts = info (argParser <**> helper)
      (  fullDesc
      <> progDesc "download large files across GFW reliably"
      <> header "rd - reliable download command line tool" )

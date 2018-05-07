module Main (main) where

import Options.Applicative
import Data.Semigroup ((<>))
import Control.Monad (guard, when, unless, forM_)
import System.Directory (createDirectoryIfMissing
                        , doesFileExist
                        , removeDirectoryRecursive)
import Control.Exception
import System.IO.Error
import System.Exit
import System.Environment (lookupEnv)
import Data.List (isPrefixOf)
import System.FilePath ((</>))
import Data.Text.Encoding (decodeUtf8)
import qualified Data.Text as T
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as LB
import qualified Data.ByteString.Lazy.Char8 as L8
import qualified Data.ByteString.Char8 as Char8
import qualified Data.HashMap.Strict as M

import Data.Aeson (Value(..))
import Network.HTTP.Simple
import Network.HTTP.Client (path)
import Formatting

import RD.Lib (sha1sumOnBytes, guessFilename)
import Type
import Opts

debug :: Show a => RDOptions -> a -> IO ()
debug opts msg = when (verbose opts) $ print msg

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

-- | try fetch block data from http, if fetched data matches sha1sum, write it
-- to blockTargetFile and return IO True. Otherwise, return IO False.
fetchBlockFromHttp :: RDOptions -> FetchBlockParam -> IO Bool
fetchBlockFromHttp opts fbp = do
  let (blockId, start, end, sha1sum) = fbpBlockWithChecksum fbp
      filename = fbpFilename fbp
      rangeHeader = "bytes=" <> Char8.pack (show start) <> "-"
                             <> Char8.pack (show end)
  -- TODO capture http error. implement retry here.
  debug opts $ "downloading " <> filename <> " block " <> show blockId
  req <- parseRequest $ T.unpack $ fbpUrl fbp
  response <- httpLBS $ addRequestHeader "Range" rangeHeader req
  let bodyLBS = getResponseBody response
  if (decodeUtf8 . LB.toStrict . sha1sumOnBytes) bodyLBS == sha1sum then do
      let blockTargetFile = fbpBlockTargetFile fbp
      debug opts $ "writing block data to " <> blockTargetFile
      LB.writeFile blockTargetFile bodyLBS
      return True
  else do
      putStrLn $ "sha1sum verification failed for " <> filename <> " block " <> show blockId
      return False

-- | return block target file name (just base filename, no dir info)
getBlockFilename :: RDResponse -> BlockWithChecksum -> FilePath
getBlockFilename rdResp blockWithChecksum =
  let padding = bestPadding $ respBlockCount rdResp
      (blockId, _, _, sha1sum) = blockWithChecksum in
  formatToString ("block" % left padding '0' % "_" % stext) blockId sha1sum

-- | fetch a single block, return IO True on success
fetchBlock :: RDOptions -> T.Text -> RDResponse -> BlockID -> IO Bool
fetchBlock opts url rdResp blockId = do
  let blockWithChecksum = respBlocks rdResp !! fromIntegral blockId
      filename = guessFilename url
      blockFileDir = tempDir opts </> filename
      blockFilename = getBlockFilename rdResp blockWithChecksum
      blockTargetFile = blockFileDir </> blockFilename
  result <- catchJust (guard . isPermissionError)
            (do
              createDirectoryIfMissing True blockFileDir
              return True)
            (\_ -> do
               putStrLn $ "Create temp dir " <> blockFileDir <> " failed. Make sure you have correct permission."
               return False)
  if not result then
      return False
  else do
    fileExist <- doesFileExist blockTargetFile
    if fileExist then
        return True
    else
        fetchBlockFromHttp opts (FetchBlockParam url filename blockWithChecksum blockTargetFile)

-- | return block target file names in correct order.
getBlockTargetFilenames :: RDOptions -> RDResponse -> [FilePath]
getBlockTargetFilenames opts rdResp =
  let blockFileDir = tempDir opts </> guessFilename (respPath rdResp)
      getBlockTargetFile blockWithChecksum = blockFileDir </> getBlockFilename rdResp blockWithChecksum in
  map getBlockTargetFile (respBlocks rdResp)

-- | combine downloaded blocks to the final file. Return IO True on success.
combineBlocks :: RDOptions -> RDResponse -> IO Bool
combineBlocks opts rdResp = do
  let outDir = outputDir opts
      filename = guessFilename $ respPath rdResp
      targetFilename = outDir </> filename
  putStrLn $ "combining blocks to create " <> targetFilename
  forM_ (getBlockTargetFilenames opts rdResp) $ \blockFilename -> do
    debug opts $ "appending block file " <> blockFilename
    content <- LB.readFile blockFilename
    LB.appendFile targetFilename content
  putStrLn $ "file downloaded to " <> targetFilename
  unless (keepBlockData opts) $ do
    let tempdir = tempDir opts </> filename
    debug opts $ "delete temporary block data dir " <> tempdir
    removeDirectoryRecursive tempdir
  return True

-- | download file at given URL using reliable download API and block based
-- downloading.
downloadFile :: RDOptions -> T.Text -> IO Bool
downloadFile opts url = do
  req <- parseRequest $ T.unpack url
  resp <- httpJSON $ req { path="/rd" <> path req }
  let rdResp = getResponseBody resp :: RDResponse
  if not $ respOk rdResp then do
      putStrLn $ "GET /rd/ api failed: " <> show (respMsg rdResp)
      return False
  else do
      putStrLn "GET /rd/ api ok"
      putStrLn $ "Downloading file: " <> show (respPath rdResp) <> ", "
               <> humanReadableSize (respFileSize rdResp)
               <> ", " <> show (respBlockCount rdResp) <> " blocks"
      results <- mapM (fetchBlock opts url rdResp) [0..respBlockCount rdResp - 1]
      if and results then
          combineBlocks opts rdResp
      else do
          putStrLn $ (show . length . filter id) results <> " blocks failed."
          return False

cliApp :: RDOptions -> IO ()
cliApp opts = do
  debug opts $ "command line options: " <> show opts
  let dir = tempDir opts
  catchJust (guard . isPermissionError)
            (createDirectoryIfMissing True dir)
            (\_ -> die $ "Create temp dir " <> dir <> " failed. Make sure you have correct permission.")
  debug opts $ "using temp dir: " <> dir
  results <- mapM (downloadFile opts) (urls opts)
  if and results then
      putStrLn "all urls downloaded."
  else do
      die $ (show . length . filter id) results <> " urls failed."

main :: IO ()
main = cliApp =<< execParser opts
  where
    opts = info (argParser <**> helper)
      (  fullDesc
      <> progDesc "download large files across GFW reliably"
      <> header "rd - reliable download command line tool" )

module Main (main) where

import Network.Socket.Internal (PortNumber)
import Data.String (fromString)
import System.Environment (lookupEnv)
import Data.Monoid ((<>))
import Control.Concurrent.Chan
import System.Directory (setCurrentDirectory)
import qualified Data.Text as T

import Network.Wai.Handler.Warp
import Formatting
import Log
import Log.Backend.StandardOutput
-- import Network.Wai.Application.Static
import Network.Wai.Middleware.Static
import Options.Applicative
import qualified Database.Redis as R
import qualified Text.PrettyPrint.ANSI.Leijen as D

import Config
import Opts (argParser)
import App (mkWaiApp)
import Worker (startWorkers)

-- TODO use a proper config lib.
-- TODO support other env variables.
updateRDConfigFromEnv :: RDConfig -> IO RDConfig
updateRDConfigFromEnv config = do
  webroot <- lookupEnv "WEB_ROOT"
  let newConfig =
          case webroot of
            Just dir -> config {webRoot=dir}
            Nothing -> config
  withSimpleStdOutLogger $ \logger -> runLogT "Main" logger $
    logInfo_ $ "webRoot is " <> T.pack (webRoot newConfig)
  return newConfig

runApiServer :: RDConfig -> IO ()
runApiServer rdConfig = withSimpleStdOutLogger $ \logger -> do
  config <- updateRDConfigFromEnv rdConfig
  conn <- R.checkedConnect $ R.defaultConnectInfo {
            R.connectHost=redisHost config
          , R.connectPort=R.PortNumber (fromIntegral (redisPort config) :: PortNumber)
          }
  fileChan <- newChan
  let runtimeConfig = RDRuntimeConfig { rcConfig=config
                                      , rcRedisConn=conn
                                      , rcFileChan=fileChan}
  startWorkers runtimeConfig
  runLogT "Main" logger $
    logInfo_ $ sformat ("will listen on " % string % ":" % int) (host config) (port config)
  let warpSettings = ( setFdCacheDuration 10
                     . setFileInfoCacheDuration 10
                     . setPort (port config)
                     . setHost (fromString $ host config)) defaultSettings
  rdApi <- mkWaiApp runtimeConfig
  -- let staticApp = staticApp $ defaultFileServerSettings $ webRoot config
  -- runSettings warpSettings rdApi
  setCurrentDirectory (webRoot config)    -- static app only support serving
                                          -- from PWD
  let app = static rdApi
  runSettings warpSettings app

rdApiDescription :: String
rdApiDescription = "rd-api is an HTTP file server that provides static file hosting and reliable\n\
\download api for rd client.\n\
\\n\
\rd-api serves files under web-root. You can use it like python3 -m http.server\n\
\\n\
\In addition, if rd command line tool is used to do the download, it will\n\
\download in a reliable way by downloading in 2MiB blocks and verify checksum\n\
\for each block.\n\
\\n\
\Usage:\n\
\    server side:\n\
\        $ ls\n\
\        bigfile1 bigfile2\n\
\        $ rd-api --host 0.0.0.0 --port 8082\n\
\\n\
\    client side:\n\
\        $ rd http://server-ip:8082/bigfile1\n\
\\n\
\Reliable download is implemented this way:\n\
\\n\
\- user uses rd client to request a resource to download.\n\
\- rd client requests resource block metadata via the /rd/ api. block metadata\n\
\  contains block count, block id, block byte offset, block content sha1sum.\n\
\- rd-api calculates and serves block metadata to rd client incrementally.\n\
\  block metadata is cached in redis after calculation.\n\
\- rd client fetches block and verifies sha1sum incrementally. When all blocks\n\
\  are downloaded and verified, combine blocks to get the final resource.\n\
\- rd client will retry on http errors and sha1sum verification failures.\n\
\- rd client supports continuing a partial download. You can press Ctrl-C to\n\
\  stop download anytime, and continue later by running the same command again."

main :: IO ()
main = runApiServer =<< execParser opts
  where
    opts = info (argParser <**> helper)
      (  fullDesc
      <> header "rd-api - reliable download server"
      <> (progDescDoc $ Just $ D.string rdApiDescription))

module Main (main) where

import Network.Socket.Internal (PortNumber)
import Data.String (fromString)
import System.Environment (lookupEnv)
import Data.Monoid ((<>))
import Control.Concurrent.Chan
import System.Directory (setCurrentDirectory)
import qualified Data.Text as T
import qualified Data.Text.Lazy as LT

import Web.Scotty
import Network.Wai.Handler.Warp
import Formatting
import Log
import Log.Backend.StandardOutput
-- import Network.Wai.Application.Static
import Network.Wai.Middleware.Static
import qualified Database.Redis as R

import Config
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
    logInfo_ $ "webRoot is " <> T.pack (webRoot config)
  return newConfig

main :: IO ()
main = withSimpleStdOutLogger $ \logger -> do
  config <- updateRDConfigFromEnv defaultRDConfig
  conn <- R.checkedConnect $ R.defaultConnectInfo {
            R.connectHost=redisHost config
          , R.connectPort=R.PortNumber (fromIntegral (redisPort config) :: PortNumber)
          }
  fileChan <- newChan
  let runtimeConfig = RDRuntimeConfig { config=config
                                      , redisConn=conn
                                      , fileChan=fileChan}
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

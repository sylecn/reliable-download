module Main (main) where

import Network.Socket.Internal (PortNumber)
import Data.String (fromString)
import System.Environment (lookupEnv)
import Data.Monoid ((<>))
import qualified Data.Text as T
import qualified Data.Text.Lazy as LT

import Web.Scotty
import Network.Wai.Handler.Warp (defaultSettings, setHost, setPort)
import Formatting
import Log
import Log.Backend.StandardOutput
import qualified Database.Redis as R

import App (mkApp)
import Config

-- TODO use a proper config lib.
-- TODO support other env variables.
updateRDConfigFromEnv :: RDConfig -> IO RDConfig
updateRDConfigFromEnv config = do
  webroot <- lookupEnv "WEB_ROOT"
  let newConfig =
          case webroot of
            Just dir -> config {webRoot=dir}
            Nothing -> config
  withSimpleStdOutLogger $ \logger -> do
    runLogT "Main" logger $ do
      logInfo_ $ "webRoot is " <> T.pack (webRoot config)
  return newConfig

main :: IO ()
main = withSimpleStdOutLogger $ \logger -> do
  config <- updateRDConfigFromEnv defaultRDConfig
  conn <- R.checkedConnect $ R.defaultConnectInfo {
            R.connectHost=redisHost config
          , R.connectPort=R.PortNumber $ (fromIntegral (redisPort config) :: PortNumber)
          }
  let runtimeConfig = RDRuntimeConfig { config=config
                                      , redisConn=conn
                                      }
  runLogT "Main" logger $ do
    logInfo_ $ sformat ("will listen on " % string % ":" % int) (host config) (port config)
  let opts = Options { verbose=0
                     , settings=warpSettings
                     }
          where
            warpSettings = setPort (port config)
                           (setHost (fromString $ host config) defaultSettings)
  scottyOpts opts $ mkApp runtimeConfig

module Main (main) where

import Data.String (fromString)
import System.Environment (lookupEnv)
import Data.Monoid ((<>))
import Control.Monad (mzero, when)
import Control.Monad.IO.Class (liftIO)
import System.Directory (setCurrentDirectory)

import Network.Wai.Handler.Warp
import Formatting
import Network.Wai.Middleware.Static
import Options.Applicative
import System.Log.FastLogger
import Control.Error
import System.Exit (die)
import qualified Database.Redis as R
import qualified Text.PrettyPrint.ANSI.Leijen as D

import Config
import CliVersion (cliVersion)
import Utils
import Opts (argParser)
import OptsDoc (rdApiDescription)
import App (mkWaiApp)
import Worker (startWorkers)

-- TODO use a proper config lib.
-- TODO support other env variables.
updateRDConfigFromEnv :: RDConfig -> IO RDConfig
updateRDConfigFromEnv config = do
  webroot <- lookupEnv "WEB_ROOT"
  return $ case webroot of
             Just dir -> config {webRoot=dir}
             Nothing -> config

runApiServer :: RDConfig -> MaybeT IO ()
runApiServer rdConfig = do
  rc0 <- liftIO defaultRDRuntimeConfig
  config <- liftIO $ updateRDConfigFromEnv rdConfig
  connEi <- runExceptT $ scriptIO $ R.checkedConnect $ R.defaultConnectInfo {
            R.connectHost=redisHost config
          , R.connectPort=R.PortNumber (fromIntegral (redisPort config))
          }
  conn <- case connEi of
    Left e -> do
      liftIO $ pushLogStrLn (rcLoggerSet rc0) $ toLogStr $ sformat
        ("Connect to redis at " % string % ":" % int % " failed: " % stext)
        (redisHost config) (redisPort config) e
      mzero
    Right conn ->
      return conn
  let rc = rc0 { rcConfig=config
               , rcRedisConn=conn }
  liftIO $ do
    startWorkers rc
    logl rc $ sformat ("webRoot is " % string) (webRoot config)
    logl rc $ sformat ("will listen on " % string % ":" % int) (host config) (port config)
    let warpSettings = ( setFdCacheDuration 10
                       . setFileInfoCacheDuration 10
                       . setPort (port config)
                       . setHost (fromString $ host config)) defaultSettings
    rdApi <- mkWaiApp rc
    -- static app only support serving from PWD
    setCurrentDirectory (webRoot config)
    let app = static rdApi
    runSettings warpSettings app

main :: IO ()
main = do
  rdConfig <- execParser opts
  if showVersion rdConfig then
      putStrLn $ "rd-api " <> cliVersion
  else do
    resultMaybe <- runMaybeT $ runApiServer rdConfig
    when (isNothing resultMaybe) $
      die "start rd-api failed"
    where
      opts = info (argParser <**> helper)
                  (  fullDesc
                  <> header "rd-api - reliable download server"
                  <> progDescDoc (Just $ D.string rdApiDescription))

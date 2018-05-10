module Main (main) where

import Data.String (fromString)
import System.Environment (getEnvironment)
import Data.Monoid ((<>))
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import System.Directory (setCurrentDirectory)
import Data.Maybe (fromJust)
import qualified Data.Text as T

import Network.Wai.Handler.Warp
import Formatting
import Network.Wai.Middleware.Static
import Options.Applicative
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

-- | convert Maybe String to Maybe Int
toIntMaybe :: Maybe String -> Maybe Int
toIntMaybe Nothing = Nothing
toIntMaybe (Just s) = case reads s of
                        [(i, [])] -> Just i
                        _ -> Nothing

updateRDConfigFromEnvPure :: [(String, String)] -> RDConfig -> Either T.Text RDConfig
updateRDConfigFromEnvPure env = Right
    .(\c -> maybe c (\h -> c { host=h }) (lookup "HOST" env))
    .(\c -> maybe c (\p -> c { port=p }) (toIntMaybe (lookup "PORT" env)))
    .(\c -> maybe c (\h -> c { redisHost=h }) (lookup "REDIS_HOST" env))
    .(\c -> maybe c (\p -> c { redisPort=p }) (toIntMaybe (lookup "REDIS_PORT" env)))
    .(\c -> maybe c (\d -> c { webRoot=d }) (lookup "WEB_ROOT" env))
    .(\c -> maybe c (\i -> c { fileWorkerCount=i }) (toIntMaybe (lookup "WORKER" env)))

-- | update RDConfig if some env variables are defined.
-- return IO (Right RDConfig) on success
updateRDConfigFromEnv :: RDConfig -> IO (Either T.Text RDConfig)
updateRDConfigFromEnv config = do
  alist <- getEnvironment
  return $ updateRDConfigFromEnvPure alist config

runApiServer :: RDConfig -> MaybeT IO ()
runApiServer rdConfig = do
  rc0 <- liftIO $ defaultRDRuntimeConfig rdConfig
  configE <- liftIO $ updateRDConfigFromEnv rdConfig
  configMaybe <- case configE of
    Left e -> do
      liftIO $ logl rc0 $ sformat ("Error: some config from env variable failed to parse: " % stext) e
      return Nothing
    Right config -> return $ Just config
  let config = fromJust configMaybe
  connEi <- runExceptT $ scriptIO $ R.checkedConnect $ R.defaultConnectInfo {
            R.connectHost=redisHost config
          , R.connectPort=R.PortNumber (fromIntegral (redisPort config))
          }
  connMaybe <- case connEi of
    Left e -> do
      liftIO $ do
        logl rc0 $ sformat
          ("Connect to redis at " % string % ":" % int % " failed: " % stext)
          (redisHost config) (redisPort config) e
        logl rc0 $ sformat "No redis, GET /rd/ api disabled, acting as static file server"
      return Nothing
    Right conn ->
      return $ Just conn
  let rc = case connMaybe of
             Nothing -> rc0 { rcConfig=config
                            , rcHasRedis=False }
             Just conn -> rc0 { rcConfig=config
                              , rcHasRedis=True
                              , rcRedisConn=conn }
  liftIO $ do
    if rcHasRedis rc then
        startWorkers rc
    else
        logl rc $ sformat "No redis, not starting workers"
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

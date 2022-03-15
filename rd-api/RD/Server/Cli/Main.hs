module RD.Server.Cli.Main (main) where

import Data.String (fromString)
import System.Environment (getEnvironment)
import Control.Monad (mzero, when)
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

import RD.Server.Config
import RD.CliVersion (cliVersion)
import RD.Server.Cli.Opts (argParser)
import RD.Server.Cli.OptsDoc (rdApiDescription)
import RD.Server.App (mkWaiApp)
import RD.Server.Worker (startWorkers)

-- | parse int env var, if it exists and is an int, return Right (Just i).
-- if it exists and doesn't parse, return Left msg with key and value info.
-- otherwise, return Right Nothing.
parseIntEnv :: String -> [(String, String)] -> Either T.Text (Maybe Int)
parseIntEnv key env =
  case lookup key env of
    Nothing -> Right Nothing
    Just s -> case reads s of
                  [(i, [])] -> Right $ Just i
                  _ -> Left $ "failed to parse " <> T.pack key <> " from env variable: " <> T.pack s

updateRDConfigFromEnvPure :: [(String, String)] -> RDConfig -> Either T.Text RDConfig
updateRDConfigFromEnvPure env c0 =
  (\c -> Right $ maybe c (\h -> c { host=h }) (lookup "HOST" env)) c0 >>=
  (\c -> either
           Left
           (maybe (Right c) (\i -> Right $ c { port=i }))
           (parseIntEnv "PORT" env)) >>=
  (\c -> Right $ maybe c (\h -> c { redisHost=h })
                 (lookup "REDIS_HOST" env)) >>=
  (\c -> either
           Left
           (maybe (Right c) (\i -> Right $ c { redisPort=i }))
           (parseIntEnv "REDIS_PORT" env)) >>=
  (\c -> Right $ maybe c (\d -> c { webRoot=d }) (lookup "WEB_ROOT" env)) >>=
  (\c -> either
           Left
           (maybe (Right c) (\i -> Right $ c { fileWorkerCount=i }))
           (parseIntEnv "WORKER" env))

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
      -- liftIO $ L.err (rcLogger rc0) $ L.msg $ sformat ("Error: " % stext) e
      liftIO $ errorl rc0 $ sformat ("Error: " % stext) e
      mzero    -- early exit
    Right config -> return $ Just config
  let config = fromJust configMaybe
  connEi <- runExceptT $ scriptIO $ R.checkedConnect $ R.defaultConnectInfo {
            R.connectHost=redisHost config
          , R.connectPort=R.PortNumber (fromIntegral (redisPort config))
          }
  connMaybe <- case connEi of
    Left e -> do
      liftIO $ do
        errorl rc0 $ sformat
          ("Connect to redis at " % string % ":" % int % " failed: " % stext)
          (redisHost config) (redisPort config) e
        warnl rc0 $ sformat "No redis, GET /rd/ api disabled, acting as static file server"
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
        warnl rc $ sformat "No redis, not starting workers"
    infol rc $ sformat ("rd-api " % string) cliVersion
    infol rc $ sformat ("webRoot is " % string) (webRoot config)
    infol rc $ sformat ("will listen on " % string % ":" % int) (host config) (port config)
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

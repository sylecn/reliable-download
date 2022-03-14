module Config where

import qualified Database.Redis as R
import Control.Concurrent.Chan
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as Char8
import qualified Data.Text as T
import Control.Monad.IO.Class

import qualified System.Logger as L

import Type

-- | rd-api configuration, supports cli arguments or env variable.
data RDConfig = RDConfig {
      host :: String
    , port :: Int
    , redisHost :: String
    , redisPort :: Int
    , webRoot :: FilePath
    , fileWorkerCount :: Int
    , verbose :: Bool
    , showVersion :: Bool } deriving (Show)

data RDRuntimeConfig = RDRuntimeConfig {
      rcConfig :: RDConfig
    , rcRedisConn :: R.Connection
    , rcHasRedis :: Bool
    , rcFileChan :: Chan FillBlockParam
    , rcLogger :: L.Logger }

errorl :: MonadIO m => RDRuntimeConfig -> T.Text -> m ()
errorl rc msg = do
  let logger = rcLogger rc
  L.err logger $ L.msg msg
  L.flush logger

warnl :: MonadIO m => RDRuntimeConfig -> T.Text -> m ()
warnl rc msg = do
  let logger = rcLogger rc
  L.warn logger $ L.msg msg
  L.flush logger

infol :: MonadIO m => RDRuntimeConfig -> T.Text -> m ()
infol rc msg = do
  let logger = rcLogger rc
  L.info logger $ L.msg msg
  L.flush logger

debugl :: MonadIO m => RDRuntimeConfig -> T.Text -> m ()
debugl rc msg = L.debug (rcLogger rc) $ L.msg msg

flushl :: MonadIO m => RDRuntimeConfig -> m ()
flushl rc = L.flush (rcLogger rc)

defaultRDConfig :: RDConfig
defaultRDConfig = RDConfig {
                    host = "0.0.0.0"
                  , port = 8082
                  , redisHost = "127.0.0.1"
                  , redisPort = 6379
                  , webRoot = "/nonexistent"
                  , fileWorkerCount = 2
                  , verbose = False
                  , showVersion = False
                  }

defaultRDRuntimeConfig :: RDConfig -> IO RDRuntimeConfig
defaultRDRuntimeConfig config = do
  conn <- R.connect R.defaultConnectInfo
  fileChan <- newChan
  let logLevel = if verbose config then L.Debug else L.Info
      logSettings = (L.setFormat (Just "%Y-%0m-%0dT%0H:%0M:%0S") .
                     L.setLogLevel logLevel .
                     L.setDelimiter "  ") L.defSettings
  logger <- L.new logSettings
  return RDRuntimeConfig {
               rcConfig=config
             , rcRedisConn=conn
             , rcHasRedis=True
             , rcFileChan=fileChan
             , rcLogger=logger }

-- | the redis hash key used to store cached sha1sum for given FillBlockParam
blockSha1sumHashKey :: FillBlockParam -> B.ByteString
blockSha1sumHashKey fbp = Char8.pack (fbpFilepath fbp) <> "_" <> (Char8.pack . show) (fbpBlockSize fbp)

-- | the redis hash key sub key, used to store the sha1sum for that blockId.
blockIdKey :: BlockID -> B.ByteString
blockIdKey = Char8.pack . show

-- | the redis string key used to track whether this file and blockSize is
-- new|working|done.
fileStatusKey :: FillBlockParam -> B.ByteString
fileStatusKey fbp = blockSha1sumHashKey fbp <> "_status"

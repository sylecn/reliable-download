module Config where

import qualified Database.Redis as R
import Control.Concurrent.Chan
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as Char8
import Data.Monoid ((<>))

import System.Log.FastLogger

import Type

-- | rd-api configuration, supports cli arguments or env variable.
data RDConfig = RDConfig {
      host :: String
    , port :: Int
    , redisHost :: String
    , redisPort :: Int
    , webRoot :: FilePath
    , fileWorkerCount :: Int
    , showVersion :: Bool } deriving (Show)

data RDRuntimeConfig = RDRuntimeConfig {
      rcConfig :: RDConfig
    , rcRedisConn :: R.Connection
    , rcHasRedis :: Bool
    , rcFileChan :: Chan FillBlockParam
    , rcLoggerSet :: LoggerSet
    , rcLoggerTimeCache :: IO FormattedTime }

defaultRDConfig :: RDConfig
defaultRDConfig = RDConfig {
                    host = "0.0.0.0"
                  , port = 8082
                  , redisHost = "127.0.0.1"
                  , redisPort = 6379
                  , webRoot = "/nonexistent"
                  , fileWorkerCount = 2
                  , showVersion = False
                  }

defaultRDRuntimeConfig :: IO RDRuntimeConfig
defaultRDRuntimeConfig = do
  conn <- R.connect R.defaultConnectInfo
  fileChan <- newChan
  loggerSet <- newStdoutLoggerSet defaultBufSize
  loggerTimeCache <- newTimeCache simpleTimeFormat
  return RDRuntimeConfig {
               rcConfig=defaultRDConfig
             , rcRedisConn=conn
             , rcHasRedis=True
             , rcFileChan=fileChan
             , rcLoggerSet=loggerSet
             , rcLoggerTimeCache=loggerTimeCache }

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

module DB where

import qualified Data.Text as T
import qualified Data.ByteString as B
import qualified Database.Redis as R

import Config
import Utils

-- | insert a key value to db, if key does not exist in db.
insertIfNotExist :: RDRuntimeConfig -> B.ByteString -> B.ByteString -> IO (Either T.Text Bool)
insertIfNotExist rc key value = do
  redisReply <- R.runRedis (rcRedisConn rc) $ R.setnx key value
  case redisReply of
    Left reply -> do
      let msg = "redis setnx " <> showt key <> " failed:\n\t" <> showt reply
      logl rc msg
      return $ Left "insertIfNotExist on DB failed"
    Right v -> return $ Right v

get :: RDRuntimeConfig -> B.ByteString -> IO (Either T.Text (Maybe B.ByteString))
get rc key = do
  redisReply <- R.runRedis (rcRedisConn rc) $ R.get key
  case redisReply of
    Left reply -> do
      let msg = "redis get " <> showt key <> " failed: " <> showt reply
      logl rc msg
      return $ Left msg
    Right v -> return $ Right v

set :: RDRuntimeConfig -> B.ByteString -> B.ByteString -> IO (Either T.Text R.Status)
set rc key value = do
  redisReply <- R.runRedis (rcRedisConn rc) $ R.set key value
  case redisReply of
    Left reply -> do
      let msg = "redis set " <> showt key <> " to " <> showt value <> " failed: " <> showt reply
      logl rc msg
      return $ Left msg
    Right v -> return $ Right v

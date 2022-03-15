module Worker (startWorkers, sha1sumFileRange, fileRange) where

import Control.Concurrent.Chan
import System.IO (IOMode(ReadMode), withBinaryFile)
import GHC.IO.Handle (Handle, hTell, hSeek, SeekMode(AbsoluteSeek))
import Control.Monad (when, replicateM_, forever)
import Control.Concurrent (forkIO)
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as LB
import qualified Data.Text as T

import qualified Database.Redis as R
import Formatting

import Type
import Config
import Lib (sha1sumOnBytes, humanReadableSize)
import Utils

-- | read file range data as LB.ByteString. handle must be a handle to an
-- opened file.
fileRangeH :: Handle -> Integer -> Integer -> IO LB.ByteString
fileRangeH handle start end = do
  pos <- hTell handle
  when (pos /= start) $ hSeek handle AbsoluteSeek start
  LB.hGet handle $ fromIntegral (end - start + 1)

-- | get file content in given range as IO LB.ByteString
fileRange :: FilePath -> Integer -> Integer -> IO LB.ByteString
fileRange filepath start end =
  withBinaryFile filepath ReadMode $ \handle ->
    fileRangeH handle start end

-- | calculate sha1sum for bytes in given file's byte range. start and end is
-- inclusive. This is only used in tests.
sha1sumFileRange :: FilePath -> Integer -> Integer -> IO LB.ByteString
sha1sumFileRange filepath start end = sha1sumOnBytes <$> fileRange filepath start end

-- | a file worker fetch FillBlockParam from fileChan, then calculate sha1sum
-- for all blocks and write result to redis. then mark the file as done.
fileWorker :: RDRuntimeConfig -> IO ()
fileWorker rc = forever $ do
  infol rc ("fileWorker is waiting for jobs..." :: T.Text)
  fbp <- readChan (rcFileChan rc)
  let filepath = fbpFilepath fbp
      conn = rcRedisConn rc
  -- calculate sha1sum for each block and write result to redis hash
  infol rc $ "fileWorker working on " <> showt filepath
  results <- withBinaryFile filepath ReadMode $ \handle -> do
    let hashKey = blockSha1sumHashKey fbp
    mapM (calculateSha1ForBlock conn hashKey handle) (fbpBlocks fbp)
  let resultStatus = if and results then FileStatusDone else FileStatusError
  redisReply <- R.runRedis conn $ R.set (fileStatusKey fbp) $ fsBytes resultStatus
  case redisReply of
    Left reply ->
      errorl rc $ "Set file status failed: " <> showt reply
    Right _ -> do
      debugl rc $ "Set file status to " <> showt resultStatus <> " for " <> showt filepath
      infol rc $ sformat
        ("fileWorker done for " % string % ", " % stext % ", " % int % " blocks")
        filepath (humanReadableSize (fbpFileSize fbp)) (length (fbpBlocks fbp))
  return ()
    where
      -- | calculate sha1 for a single block. return IO True on success.
      calculateSha1ForBlock :: R.Connection -> B.ByteString -> Handle -> Block -> IO Bool
      calculateSha1ForBlock conn hashKey handle (blockId, start, end) = do
        redisReply <- R.runRedis conn $ R.hget hashKey (blockIdKey blockId)
        case redisReply of
          Left reply -> do
            errorl rc $ "redis hget failed on " <> showt hashKey <> ": " <> showt reply
            return False
          Right sha1sumMaybe ->
            case sha1sumMaybe of
              Just _sha1sum -> do
                debugl rc $ "skip calculated block " <> showt blockId
                return True
              Nothing -> do
                blockContent <- fileRangeH handle start end
                let blockSha1 = LB.toStrict $ sha1sumOnBytes blockContent
                redisReply2 <- R.runRedis conn $ R.hset hashKey (blockIdKey blockId) blockSha1
                case redisReply2 of
                  Left reply -> do
                    errorl rc $ "redis hset failed on " <> showt hashKey <> ": " <> showt reply
                    return False
                  Right n ->
                    if n > 0 then
                      do
                        debugl rc $ "redis hset " <> showt hashKey <> " " <> showt blockId <> " ok"
                        return True
                     else
                        return False

startWorkers :: RDRuntimeConfig -> IO ()
startWorkers rc = do
  let workerCount = fileWorkerCount $ rcConfig rc
  infol rc $ "creating " <> showt workerCount <> " file worker(s)"
  replicateM_ workerCount (forkIO $ fileWorker rc)

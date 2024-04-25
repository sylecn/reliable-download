module RD.Client.Progress
    ( emptyProgress
    , incrementDLFileCount
    , incrementTotalBlockCount
    , incrementDownloadedBlockCount
    , setCurrentFileName
    , setCurrentFileTotalBlockCount
    , showProgress
    , showProgressAllDone
    , showProgressLoop) where

import Control.Concurrent.MVar
import qualified Data.Text as T
import Control.Concurrent (threadDelay)

import Formatting

import RD.Client.Types
import RD.Client.Logging

emptyProgress :: Progress
emptyProgress = Progress {
                  piTotalFileCount=0
                , piDownloadedFileCount=0
                , piTotalBlockCount=0
                , piDownloadedBlockCount=0
                , piCurrentFileName=""
                , piCurrentFileTotalBlockCount=0
                , piCurrentFileDownloadedBlockCount=0}

-- | increment piDownloadedFileCount by n
incrementDLFileCount :: RDClientRuntimeConfig -> Int -> IO ()
incrementDLFileCount rc n =
  modifyMVar_ (rdProgress rc) (\p -> return p {piDownloadedFileCount=piDownloadedFileCount p + n})

-- | increment piTotalBlockCount by n
incrementTotalBlockCount :: RDClientRuntimeConfig -> Int -> IO ()
incrementTotalBlockCount rc n =
  modifyMVar_ (rdProgress rc) (\p -> return p {piTotalBlockCount=piTotalBlockCount p + n})

-- | increment piDownloadedBlockCount and piCurrentFileDownloadedBlockCount by n
incrementDownloadedBlockCount :: RDClientRuntimeConfig -> Int -> IO ()
incrementDownloadedBlockCount rc n =
  modifyMVar_ (rdProgress rc)
              (\p -> return p
                     { piDownloadedBlockCount=piDownloadedBlockCount p + n
                     , piCurrentFileDownloadedBlockCount=piCurrentFileDownloadedBlockCount p + n})

-- | set piCurrentFileName
setCurrentFileName :: RDClientRuntimeConfig -> T.Text -> IO ()
setCurrentFileName rc fnFromUrl =
    modifyMVar_ (rdProgress rc) (\p -> return p {piCurrentFileName=fnFromUrl})

-- | set piCurrentFileTotalBlockCount to n, reset piCurrentFileDownloadedBlockCount to 0
setCurrentFileTotalBlockCount :: RDClientRuntimeConfig -> Int -> IO ()
setCurrentFileTotalBlockCount rc n = do
  modifyMVar_ (rdProgress rc)
              (\p -> return p { piCurrentFileTotalBlockCount=n
                              , piCurrentFileDownloadedBlockCount=0 })

-- | show download progress in console. it will not touch progress MVar.
showProgress1 :: RDClientRuntimeConfig -> Progress -> IO ()
showProgress1 rc p = do
  let dlblockc = piCurrentFileDownloadedBlockCount p
      totalblockc = piCurrentFileTotalBlockCount p
  infol rc $ sformat
      ("progress: [" % int % "%] " % int % "/" % int % " blocks, " % stext)
      ((dlblockc * 100) `div` totalblockc) dlblockc totalblockc
      (piCurrentFileName p)

-- -- | show download progress in console. used to force show 100% progress msg when a file is fully downloaded.
showProgress :: RDClientRuntimeConfig -> IO ()
showProgress rc = showProgress1 rc =<< readMVar (rdProgress rc)

-- | show a final progress when all DL completed.
showProgressAllDone :: RDClientRuntimeConfig -> IO ()
showProgressAllDone rc = do
  progress <- readMVar (rdProgress rc)
  let totalblockc = piTotalBlockCount progress
      totalfilec = piTotalFileCount progress
  infol rc $ sformat
      ("All urls downloaded. " % int % " files, " % int % " blocks.")
      totalfilec totalblockc

-- | show progress if at least one new block is fetched since last
-- time. Otherwise, give a hint there may be a DL hang. when all blocks are
-- fetched, return -1
showProgressMaybe :: RDClientRuntimeConfig -> Int -> IO Int
showProgressMaybe rc lastDownloadedBlockCount = do
  p <- readMVar (rdProgress rc)
  let newDLBC = piDownloadedBlockCount p
  if newDLBC > lastDownloadedBlockCount
    then do
      showProgress1 rc p
      return newDLBC
    else
      if piDownloadedBlockCount p < piTotalBlockCount p
        then do
          warnl rc $ sformat ("No block fetched in last " % int % " seconds")
                (progressInterval (rdOptions rc))
          return lastDownloadedBlockCount
        else
          return (-1)

-- | show download progress in console. designed to run in a thread.
showProgressLoop :: RDClientRuntimeConfig -> Int -> IO ()
showProgressLoop rc lastDownloadedBlockCount = do
  threadDelay (progressInterval (rdOptions rc) * 1000000)
  newCount <- showProgressMaybe rc lastDownloadedBlockCount
  case newCount of
    -1 -> return ()
    _ -> showProgressLoop rc newCount

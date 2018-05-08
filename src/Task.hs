module Task ( Task
            , newTask
            , addTask
            , addTasks
            , getTaskResults
            , ) where

import Control.Concurrent (forkIO)
import Control.Monad (replicateM, replicateM_, forever)
import Control.Concurrent.MVar
import Control.Concurrent.Chan
import Control.Exception

-- | submit actions to jobChan, worker will run it and put result in
-- resultChan.
worker :: Chan (IO a) -> Chan a -> IO ()
worker jobChan resultChan = forever $ do
  action <- readChan jobChan
  r <- action
  writeChan resultChan r

data Task a = Task {
      taskCount :: MVar Int
    , taskClosed :: MVar Bool
    , taskJobChan :: Chan (IO a)
    , taskResultChan :: Chan a }

data TaskException = TaskClosed deriving Show

instance Exception TaskException

-- | create a new task runner. TODO how to terminate workers when all job has
-- finished and task is closed?
newTask :: Int -> IO (Task a)
newTask n = do
  taskCountMVar <- newMVar 0
  taskClosedMVar <- newMVar False
  chan1 <- newChan
  chan2 <- newChan
  let result = Task {
                 taskCount=taskCountMVar
               , taskClosed=taskClosedMVar
               , taskJobChan=chan1
               , taskResultChan=chan2
               }
  replicateM_ n $ forkIO $ worker (taskJobChan result) (taskResultChan result)
  return result

-- | add action to task
addTask :: Task a -> IO a -> IO ()
addTask task action = do
  let tclosed = taskClosed task
      tcount = taskCount task
  closed <- takeMVar tclosed
  if closed then do
      putMVar tclosed True
      throwIO TaskClosed
  else do
      writeChan (taskJobChan task) action
      count <- takeMVar tcount
      putMVar tcount (count + 1)
      putMVar tclosed False

-- | add a list of actions to task
addTasks :: Task a -> [IO a] -> IO ()
addTasks task actions = do
  let tclosed = taskClosed task
  let tcount = taskCount task
  closed <- takeMVar tclosed
  if closed then do
      putMVar tclosed True
      throwIO TaskClosed
  else do
      writeList2Chan (taskJobChan task) actions
      count <- takeMVar tcount
      putMVar tcount (count + length actions)
      putMVar tclosed False

-- | this is a blocking get. it will wait for all tasks to finish and return
-- result. this will also mark the Task as closed so no new task can be pushed
-- to it.
getTaskResults :: Task a -> IO [a]
getTaskResults task = do
  let tclosed = taskClosed task
  closed <- takeMVar tclosed  -- don't allow add new task when getTaskResults
                              -- is called.
  if closed then do
      putMVar tclosed True
      throwIO TaskClosed    -- can't run getTaskResults twice.
  else do
      putMVar tclosed True
      n <- readMVar (taskCount task)
      replicateM n (readChan (taskResultChan task))

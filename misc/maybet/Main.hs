-- import Control.Monad
-- import Control.Monad (mzero)
import Control.Monad.Trans.Maybe
import Control.Monad.Trans.Class (lift)
import Data.Foldable (forM_)

checkA :: MaybeT IO ()
checkA = do
  lift $ putStrLn "checkA"

checkB :: MaybeT IO ()
checkB = do
  lift $ putStrLn "checkB"
  -- when True mzero
  -- lift $ putStrLn "checkB after mzero"
  MaybeT $ do
    putStrLn "this should run"
    return $ Just ()
  lift $ putStrLn "will this run?"

doD :: MaybeT IO ()
doD = do
  lift $ putStrLn "doD"
  -- mzero

doC :: MaybeT IO Bool
doC = do
  lift $ putStrLn "doC"
  doD
  lift $ putStrLn "done"
  return True

main :: IO ()
main = do
  resultMaybe <- runMaybeT $ do
    -- _ <- mzero
    checkA
    checkB
    doC
  forM_ resultMaybe print

-- for checks, use MaybeT IO (), return mzero if check failed.
-- for actions that produce value, but may also fail, use MaybeT IO a, return
-- mzero if action failed, return a if action finished.
--
-- an mzero in runMaybeT context (do sequence) will skip the rest of the
-- sequence.

-- | Utils contains general functions that is useful for all haskell projects.

module Utils where

import qualified Data.Text as T

import Control.Error
import System.Log.FastLogger

import Config

-- | like show, but return a T.Text
showt :: Show a => a -> T.Text
showt = T.pack . show

-- | log a message that implements ToLogStr
logl :: ToLogStr a => RDRuntimeConfig -> a -> IO ()
logl rc msg = do
  ts <- rcLoggerTimeCache rc
  pushLogStrLn (rcLoggerSet rc) $ toLogStr ts <> " " <> toLogStr msg

-- | signal an exception if given eitherValue is a Left.
throwOnLeft :: Monad m => Either T.Text a -> ExceptT T.Text m ()
throwOnLeft eitherValue =
    case eitherValue of
      Left e -> throwE e
      Right _value -> return ()

-- | signal an exception with specified msg if given eitherValue is a
-- Left. Original Left msg is ignored.
throwOnLeftMsg :: Monad m => Either T.Text a -> T.Text -> ExceptT T.Text m ()
throwOnLeftMsg eitherValue msg =
    case eitherValue of
      Left _ -> throwE msg
      Right _value -> return ()

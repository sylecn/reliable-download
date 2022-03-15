module RD.Client.Logging
    ( debugl
    , infol
    , warnl
    , errorl
    ) where

import qualified Data.Text as T

import qualified System.Logger as L

import RD.Client.Types

-- | log a msg using given log level
clientLogl :: L.Level -> RDClientRuntimeConfig -> T.Text -> IO ()
clientLogl level rc msg = do
  let logger = rdLogger rc
  L.log logger level $ L.msg msg
  L.flush logger

-- | log a debug msg
debugl :: RDClientRuntimeConfig -> T.Text -> IO ()
debugl = clientLogl L.Debug

-- | log an info msg
infol :: RDClientRuntimeConfig -> T.Text -> IO ()
infol = clientLogl L.Info

-- | log an warn msg
warnl :: RDClientRuntimeConfig -> T.Text -> IO ()
warnl = clientLogl L.Warn

-- | log an error msg
errorl :: RDClientRuntimeConfig -> T.Text -> IO ()
errorl = clientLogl L.Error

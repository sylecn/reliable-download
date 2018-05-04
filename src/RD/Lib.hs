module RD.Lib
    ( sha1sum
    , sha1sumOnBytes )
where

import qualified Data.Text.Lazy as LT
import qualified Data.Text.Lazy.Encoding as LTE
import qualified Data.ByteString.Lazy as LB
import Crypto.Hash

-- | get sha1sum hex string for given bytes
sha1sumOnBytes :: LB.ByteString -> LB.ByteString
sha1sumOnBytes bytes = LB.fromStrict $ digestToHexByteString $ (hashlazy bytes :: Digest SHA1)

-- | calculate sha1sum for given file
sha1sum :: LT.Text -> IO LT.Text
sha1sum filename = do
  bytes <- LB.readFile $ LT.unpack filename
  return $ LTE.decodeUtf8 $ sha1sumOnBytes bytes

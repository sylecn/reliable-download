-- | Lib contains functions that is useful for current project.

module RD.Lib
    ( sha1sum
    , sha1sumOnBytes
    , guessFilename
    , genBlocks
    , humanReadableSize )
where

import qualified Data.Text as T
import qualified Data.Text.Lazy as LT
import qualified Data.Text.Lazy.Encoding as LTE
import qualified Data.ByteString.Lazy as LB
import Crypto.Hash (digestToHexByteString, hashlazy, Digest, SHA1)
import Formatting hiding (bytes)

import RD.Types

-- | convert byte number to MiB. small number will become 0.
humanReadableSize :: Integer -> T.Text
humanReadableSize bytes =
  let bytesDouble = fromInteger bytes / (1048576 :: Double) in
    if bytesDouble < 1.0 then
      "<1.0 MiB"
    else
      sformat (fixed 1 % " MiB") bytesDouble

-- | get sha1sum hex string for given bytes
sha1sumOnBytes :: LB.ByteString -> LB.ByteString
sha1sumOnBytes bytes = LB.fromStrict $ digestToHexByteString (hashlazy bytes :: Digest SHA1)

-- | calculate sha1sum for given file
sha1sum :: LT.Text -> IO LT.Text
sha1sum filename = do
  bytes <- LB.readFile $ LT.unpack filename
  return $ LTE.decodeUtf8 $ sha1sumOnBytes bytes

-- | guess filename from URL or HTTP Path
guessFilename :: T.Text -> FilePath
guessFilename = T.unpack . last . T.splitOn "/"

-- | generate blocks for given fileSize and blockSize. This break the file to
-- size of blockSize. Last block may have a smaller size.
genBlocks :: Integer -> Integer -> [Block]
genBlocks fileSize blockSize = if fileSize == 0 then
                                   []
                               else
                                   go (0 :: Integer) (0 :: Integer) []
  where
    go :: Integer -> Integer -> [Block] -> [Block]
    go blockId startByte accumulator
      | fileSize - startByte == blockSize =
        reverse ((blockId, startByte, fileSize - 1) : accumulator)
      | fileSize - startByte > blockSize =
        go (blockId + 1) (startByte + blockSize)
          ((blockId, startByte, startByte + blockSize - 1) : accumulator)
      | startByte < fileSize =
        reverse ((blockId, startByte, fileSize - 1) : accumulator)
      | otherwise = reverse accumulator

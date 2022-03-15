module RD.Types where

import qualified Data.ByteString.Char8 as Char8
import qualified Data.ByteString as B
import qualified Data.Text as T

import Data.Aeson

type BlockID = Integer
type Block = (BlockID, Integer, Integer)
type BlockWithChecksum = (BlockID, Integer, Integer, T.Text)

-- | fetch sha1sum from BlockWithChecksum
getBlockSha1sum :: BlockWithChecksum -> T.Text
getBlockSha1sum (_, _, _, sha1sum) = sha1sum

-- | fetch blockId from BlockWithChecksum
getBlockId :: BlockWithChecksum -> BlockID
getBlockId (blockId, _, _, _) = blockId

data FileStatus
    = FileStatusWorking
    | FileStatusError
    | FileStatusDone
    | FileStatusUnknown    -- unexpected/unknown status
    deriving (Eq)

instance Show FileStatus where
    show FileStatusWorking = "working"
    show FileStatusError = "error"
    show FileStatusDone = "done"
    show FileStatusUnknown = "unknown"

fsBytes :: FileStatus -> B.ByteString
fsBytes = Char8.pack . show

fsFromBytes :: B.ByteString -> FileStatus
fsFromBytes bs =
    case bs of
      "working" -> FileStatusWorking
      "error" -> FileStatusError
      "done" -> FileStatusDone
      _ -> FileStatusUnknown

data FillBlockParam = FillBlockParam {
      fbpFilepath :: FilePath
    , fbpBlockSize :: Integer
    , fbpFileSize :: Integer
    , fbpBlocks :: [Block]}

data RDResponse = RDResponse {
      respOk :: Bool
    , respMsg :: T.Text
    , respPath :: T.Text
    , respFilePath :: String
    , respBlockSize :: T.Text  -- currently it's fixed 2MiB
    , respFileSize :: Integer
    , respBlockCount :: Integer
    , respBlocks :: [BlockWithChecksum]}

rdErrorResponse :: RDResponse
rdErrorResponse = RDResponse {
      respOk=False
    , respMsg="error"
    , respPath=""
    , respFilePath=""
    , respBlockSize=""
    , respFileSize= -1
    , respBlockCount= -1
    , respBlocks=[]}

instance FromJSON RDResponse where
    parseJSON = withObject "RDResponse" $ \v -> RDResponse
      <$> v .: "ok"
      <*> v .: "msg"
      <*> v .: "path"
      <*> v .: "filepath"
      <*> v .: "block_size"
      <*> v .: "file_size"
      <*> v .: "block_count"
      <*> v .: "blocks"

instance ToJSON RDResponse where
    toJSON (RDResponse ok msg path filepath blockSize
                       fileSize blockCount blocks) =
        object [ "ok" .= ok
               , "msg" .= msg
               , "path" .= path
               , "filepath" .= filepath
               , "block_size" .= blockSize
               , "file_size" .= fileSize
               , "block_count" .= blockCount
               , "blocks" .= blocks ]

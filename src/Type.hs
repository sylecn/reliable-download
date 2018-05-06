module Type where

import qualified Data.Text as T

type BlockID = Integer
type Block = (BlockID, Integer, Integer)
type BlockWithChecksum = (BlockID, Integer, Integer, T.Text)

data FillBlockParam = FillBlockParam {
      fbpFilepath :: FilePath
    , fbpBlockSize :: Integer
    , fbpFileSize :: Integer
    , fbpBlocks :: [Block]}

{-# LANGUAGE DisambiguateRecordFields, FlexibleInstances #-}

module Data.IP
	( IPv4 (..)
	, computeChecksum
	, fillChecksum
	, module Data.IPv6
	) where

import qualified Data.ByteString.Lazy as B
import Data.Binary
import Data.Binary.Put
import Data.Binary.Get
import Data.List
import Text.PrettyPrint
import Data.IPv6
import Data.Bits
import Control.Monad (sequence)

data IPv4 = IPv4 B.ByteString deriving (Eq, Ord, Show)

instance Binary IPv4 where
	put (IPv4 b) = putLazyByteString b
	get = getLazyByteString 4 >>= return . IPv4

data IPv4Flag = DF | MF | Res deriving (Eq, Ord, Show)

instance Enum [IPv4Flag] where
	fromEnum xs = foldl' (.|.) 0 $ map fromEnum1 xs
	toEnum f = map snd $ filter fst [(testBit f 0, Res), (testBit f 1, MF), (testBit f 2, DF)]

fromEnum1 DF   = 4
fromEnum1 MF   = 2
fromEnum1 Res  = 1

data IPv4Header =
	IPv4Hdr { hdrLength		:: Int
		, version		:: Int
		, tos			:: Int
		, payloadLength		:: Int
		, ipID			:: Int
		, flags			:: [IPv4Flag]
		, fragmentOffset	:: Int
		, ttl			:: Int
		, protocol		:: Int
		, checksum		:: Word16
		, source		:: IPv4
		, destination		:: IPv4
	} deriving (Eq, Ord, Show)

dummyIPv4Header = IPv4Hdr 5 4 0 0 0 [] 0 255 0 0 ipv4zero ipv4zero

ipv4zero = IPv4 (B.pack [0,0,0,0])

instance Binary IPv4Header where
  put (IPv4Hdr ihl ver tos len id flags off ttl prot csum src dst) = do
	pW8 $ (ihl .&. 0xF) .|. (ver `shiftL` 4 .&. 0xF0)
	pW8 tos
	pW16 len
	pW16 id
	let offFlags = (off .&. 0x1FFF) .|. fromIntegral (fromEnum flags `shiftL` 13)
	pW16 offFlags
	pW8 ttl
	pW8 prot
	putWord16be csum
	put src
	put dst

  get = do
	ihlVer <- gW8
	let ihl = (ihlVer .&. 0xF)
	    ver = (ihlVer `shiftR` 4) .&. 0xF
	tos <- gW8
	len <- gW16
	id  <- gW16
	offFlags <- gW16
	let off = offFlags .&. 0x1FFF
	    flags = toEnum $ offFlags `shiftR` 13
	ttl <- gW8
	prot <- gW8
	csum <- getWord16be
	src <- get
	dst <- get
	return $ IPv4Hdr ihl ver tos len id flags off ttl prot csum src dst

gW8 = getWord8 >>= return . fromIntegral
gW16 = getWord16be >>= return . fromIntegral
pW8 = putWord8 . fromIntegral
pW16 = putWord16be . fromIntegral
pW32 = putWord32be . fromIntegral

computeChecksum :: IPv4Header -> Word16
computeChecksum hdr = csum16 (encode hdr)

csum16 :: B.ByteString -> Word16
csum16 b = foldl' ( (+) . complement) 0 words
  where
  words :: [Word16]
  words = runGet (sequence $ replicate (hdrLength $ decode b) getWord16be) b

fillChecksum :: IPv4Header -> IPv4Header
fillChecksum a = a { checksum = computeChecksum a }

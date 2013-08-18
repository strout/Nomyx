-----------------------------------------------------------------------------
--
-- Module      :  Utils
-- Copyright   :
-- License     :  AllRightsReserved
--
-- Maintainer  :
-- Stability   :
-- Portability :
--
-- |
--
-----------------------------------------------------------------------------

{-# LANGUAGE NamedFieldPuns #-}
    
module Utils where

import Data.Maybe
import Data.Char
import Control.Monad.State
import Types
import Language.Nomyx
import Language.Nomyx.Game
import Data.Lens
import Control.Category hiding ((.))
import Safe
import Control.Concurrent.STM
import qualified Data.Acid.Advanced as A (query', update')
   
-- | this function will return just a if it can cast it to an a.
maybeRead :: Read a => String -> Maybe a
maybeRead = fmap fst . listToMaybe . reads

-- | Replaces all instances of a value in a list by another value.
replace :: Eq a => a   -- ^ Value to search
        -> a   -- ^ Value to replace it with
        -> [a] -- ^ Input list
        -> [a] -- ^ Output list
replace x y = map (\z -> if z == x then y else z)

yes = ["o", "oui", "y", "yes", "v", "vrai", "true"]
toLowerS = map toLower
isYes a = toLowerS a `elem` yes

-- | generic function to say things on transformers like GameState, ServerState etc.
say :: String -> StateT a IO ()
say = lift . putStrLn

nomyxURL :: Network -> String
nomyxURL (Network host port) = "http://" ++ host ++ ":" ++ (show port)

getPlayersName :: PlayerNumber -> Session -> IO PlayerName
getPlayersName pn s = do
   pfd <- A.query' (acidProfileData $ _profiles s) (AskProfileData pn)
   return $ _pPlayerName $ _pPlayerSettings $ fromJustNote ("getPlayersName: no profile for pn=" ++ (show pn)) pfd

getPlayersName' :: Game -> PlayerNumber -> PlayerName
getPlayersName' g pn = do
   case find ((==pn) . getL playerNumber) (_players g) of
      Nothing -> error "getPlayersName: No player by that number in that game"
      Just pm -> _playerName pm

-- | returns the game the player is in
getPlayersGame :: PlayerNumber -> Session -> IO (Maybe LoggedGame)
getPlayersGame pn s = do
   pfd <- A.query' (acidProfileData $ _profiles s) (AskProfileData pn)
   let mgn = _pViewingGame $ fromJustNote "getPlayersGame" pfd
   return $ do
      gn <- mgn
      find ((== gn) . getL (game >>> gameName)) (_games $ _multi s) --checks if any game by that name exists

getAllProfiles :: Session -> IO [ProfileData]
getAllProfiles s = A.query' (acidProfileData $ _profiles s) AskProfilesData


getPlayer :: Game -> PlayerNumber -> Maybe PlayerInfo
getPlayer g pn = find ((==pn) . getL playerNumber) (_players g)

-- | finds the corresponding game in the multistate and replaces it.
modifyGame :: LoggedGame -> StateT Multi IO ()
modifyGame lg = do
   gs <- access games
   case find (== lg) gs of
      Nothing -> error "modifyGame: No game by that name"
      Just oldg -> do
         let newgs = replace oldg lg gs
         games ~= newgs
         return ()

execWithMulti :: UTCTime -> StateT Multi IO () -> Multi -> IO Multi
execWithMulti t ms m = do
   let setTime g = (game >>> currentTime) ^= t $ g
   let m' = games `modL` (map setTime) $ m
   execStateT ms m'

modifyProfile :: PlayerNumber -> (ProfileData -> ProfileData) -> StateT Session IO ()
modifyProfile pn mod = do
   s <- get
   pfd <- A.query' (acidProfileData $ _profiles s) (AskProfileData pn)
   A.update' (acidProfileData $ _profiles s) (SetProfileData (mod $ fromJustNote "modifyProfile" pfd))
   return ()

getProfile :: MonadIO m => Session -> PlayerNumber -> m (Maybe ProfileData)
getProfile s pn = A.query' (acidProfileData $ _profiles s) (AskProfileData pn)

getProfile' :: MonadIO m => (TVar Session) -> PlayerNumber -> m (Maybe ProfileData)
getProfile' ts pn = do
   s <- liftIO $ atomically $ readTVar ts
   getProfile s pn


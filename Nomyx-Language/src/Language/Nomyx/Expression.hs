{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE MultiParamTypeClasses #-} 
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE DeriveGeneric #-}

-- | This module containt the type definitions necessary to build a Nomic rule. 
module Language.Nomyx.Expression where

import Data.Typeable
import Data.Time
import GHC.Generics
import Control.Applicative hiding (Const)
import Data.Lens.Template
import Control.Monad.Error
import Control.Shortcut
import System.Random

type PlayerNumber = Int
type PlayerName = String
type RuleNumber = Int
type RuleName = String
type RuleDesc = String
type RuleText = String
type RuleCode = String
type EventNumber = Int
type EventName = String
type VarName = String
type Code = String
type OutputNumber = Int
type InputNumber = Int

-- * Nomyx Expression

data Eff = Effect | NoEffect deriving (Typeable)

type Effect = 'Effect
type NoEffect = 'NoEffect

-- | A Nomex (Nomyx Expression) allows the players to write rules.
-- within the rules, you can access and modify the state of the game.
type Nomex = Exp Effect

-- | A NomexNE (Nomyx Expression No Effect) is a specialisation of the type that guaranties
-- that the instructions will have no effects.
type NomexNE = Exp NoEffect

data Exp :: Eff -> * -> *   where
   --Variables management
   NewVar          :: (Typeable a, Show a) => VarName -> a -> Nomex (Maybe (V a))
   ReadVar         :: (Typeable a, Show a) => V a -> NomexNE (Maybe a)
   WriteVar        :: (Typeable a, Show a) => V a -> a -> Nomex Bool
   DelVar          :: (V a) -> Nomex Bool
   --Events management
   OnEvent         :: (Typeable e, Show e) => Event e -> ((EventNumber, e) -> Nomex ()) -> Nomex EventNumber
   DelEvent        :: EventNumber -> Nomex Bool
   GetEvents       :: NomexNE [EventInfo]
   SendMessage     :: (Typeable a, Show a) => Msg a -> a -> Nomex ()
   --Rules management
   ProposeRule     :: RuleInfo -> Nomex Bool
   ActivateRule    :: RuleNumber -> Nomex Bool
   RejectRule      :: RuleNumber -> Nomex Bool
   AddRule         :: RuleInfo -> Nomex Bool
   ModifyRule      :: RuleNumber -> RuleInfo -> Nomex Bool
   GetRules        :: NomexNE [RuleInfo]
   --Players management
   GetPlayers      :: NomexNE [PlayerInfo]
   SetPlayerName   :: PlayerNumber -> PlayerName -> Nomex Bool
   DelPlayer       :: PlayerNumber -> Nomex Bool
   --Outputs
   NewOutput       :: Maybe PlayerNumber -> NomexNE String -> Nomex OutputNumber
   GetOutput       :: OutputNumber -> NomexNE (Maybe String)
   UpdateOutput    :: OutputNumber -> NomexNE String -> Nomex Bool
   DelOutput       :: OutputNumber -> Nomex Bool
   --Mileacenous
   SetVictory      :: NomexNE [PlayerNumber] -> Nomex ()
   CurrentTime     :: NomexNE UTCTime
   SelfRuleNumber  :: NomexNE RuleNumber
   GetRandomNumber :: Random a => (a, a) -> Nomex a
   --Monadic bindings
   Return          :: a -> Exp e a
   Bind            :: Exp e a -> (a -> Exp e b) -> Exp e b
   ThrowError      :: String -> Exp Effect a
   CatchError      :: Nomex a -> (String -> Nomex a) -> Nomex a
   LiftEffect      :: NomexNE a -> Nomex a
   Simu            :: Nomex a -> NomexNE Bool -> NomexNE Bool


#if __GLASGOW_HASKELL__ >= 708
deriving instance Typeable Exp
deriving instance Typeable 'Effect
deriving instance Typeable 'NoEffect
#else
instance Typeable1 (Exp NoEffect) where
    typeOf1 _ = mkTyConApp (mkTyCon3 "main" "Language.Nomyx.Expression" "Exp NoEffect") []

instance Typeable1 (Exp Effect) where
    typeOf1 _ = mkTyConApp (mkTyCon3 "main" "Language.Nomyx.Expression" "Exp Effect") []
#endif

liftEffect :: NomexNE a -> Nomex a
liftEffect = LiftEffect  

instance Monad (Exp a) where
   return = Return
   (>>=) = Bind
   
instance Functor (Exp a) where
   fmap f e = Bind e $ Return . f

instance Applicative (Exp a) where
   pure = Return
   f <*> a = do
      f' <- f
      a' <- a
      return $ f' a'

instance MonadError String Nomex where
   throwError = ThrowError
   catchError = CatchError

instance Typeable a => Show (Exp NoEffect a) where
#if __GLASGOW_HASKELL__ < 708
   show e = "<" ++ (show $ typeOf e) ++ ">"
#else
   show e = "<" ++ (show $ typeRep (Proxy :: Proxy a)) ++ ">"
#endif

instance Typeable a => Show (Exp Effect a) where
#if __GLASGOW_HASKELL__ < 708
   show e = "<" ++ (show $ typeOf e) ++ ">"
#else
   show e = "<" ++ (show $ typeRep (Proxy :: Proxy a)) ++ ">"
#endif

instance (Typeable a, Typeable b) => Show (a -> b) where
    show e = '<' : (show . typeOf) e ++ ">"

-- * Variables

-- | a container for a variable name and type
data V a = V {varName :: String} deriving Typeable

-- * Events

-- | Composable events
data Event a where
   SumEvent       :: Event a -> Event a -> Event a                        -- The first event to fire will be returned
   AppEvent       :: Event (a -> b) -> Event a -> Event b                 -- Both events should fire, and then the result is returned
   PureEvent      :: a -> Event a                                         -- Create a fake event. The result is useable with no delay.
   EmptyEvent     :: Event a                                              -- An event that is never fired.
   BindEvent      :: Event a -> (a -> Event b) -> Event b                 -- A First event should fire, then a second event is constructed
   ShortcutEvents :: [Event a] -> ([Maybe a] -> Bool) -> Event [Maybe a]  -- Return the intermediate results as soon as the function evaluates to True, dismissing the events that hasn't fired yet
   SignalEvent    :: (Typeable a) => Signal a -> Event a                  -- Embed a single Signal as an Event
   LiftEvent      :: NomexNE a -> Event a                                 -- create an event containing the result of the NomexNE.
   deriving Typeable

-- | Signals
data Signal a where
   Input   :: PlayerNumber -> String -> (InputForm a) -> Signal a
   Player  :: Player    -> Signal PlayerInfo
   RuleEv  :: RuleEvent -> Signal RuleInfo
   Time    :: UTCTime   -> Signal UTCTime
   Message :: Msg a     -> Signal a
   Victory ::              Signal VictoryInfo
   deriving Typeable

-- | Type agnostic base event
data SomeSignal = forall a. (Typeable a) => SomeSignal (Signal a)

-- | Type agnostic result data
data SomeData = forall e. (Typeable e, Show e) => SomeData e
deriving instance Show SomeData

-- | Events parameters
data Player    = Arrive | Leave deriving (Typeable, Show, Eq)
data RuleEvent = Proposed | Activated | Rejected | Added | Modified | Deleted deriving (Typeable, Show, Eq)
data Msg m     = Msg String deriving (Typeable, Show)

-- | Input forms
data InputForm a where
   Text     ::                                    InputForm String
   TextArea ::                                    InputForm String
   Button   ::                                    InputForm ()
   Radio    :: (Show a, Eq a) => [(a, String)] -> InputForm a
   Checkbox :: (Show a, Eq a) => [(a, String)] -> InputForm [a]
   deriving Typeable

deriving instance Show (InputForm a)
deriving instance Show (Signal a)
deriving instance Show SomeSignal
deriving instance Eq (Signal e)
deriving instance Eq (InputForm e)
deriving instance Eq (Msg e)

instance Functor Event where
   fmap f a = pure f <*> a

instance Applicative Event where
   pure = PureEvent
   (<*>) = AppEvent

instance Alternative Event where
   (<|>) = SumEvent
   empty = EmptyEvent

instance Monad Event where
   (>>=) = BindEvent
   return = PureEvent

instance MonadPlus Event where
   mplus = SumEvent
   mzero = EmptyEvent

instance Shortcutable Event where
   shortcut = ShortcutEvents

-- EventInfo

data EventInfo = forall e. (Typeable e, Show e) =>
   EventInfo {_eventNumber :: EventNumber,
              _ruleNumber  :: RuleNumber,
              event        :: Event e,
              handler      :: EventHandler e,
              _evStatus    :: Status,
              _env         :: [SignalOccurence]}

data SignalAddressElem = SumR | SumL | AppR | AppL | BindR | BindL | Shortcut deriving (Show, Read, Ord, Eq, Generic)
type SignalAddress = [SignalAddressElem]

data SignalData = forall e. (Typeable e, Show e) =>
   SignalData {signal     :: Signal e,
               signalData :: e}

data SignalOccurence = SignalOccurence {_signalOccData    :: SignalData,
                                        _signalOccAddress :: SignalAddress}

type EventHandler e = (EventNumber, e) -> Nomex ()

deriving instance Show SignalData
deriving instance Show SignalOccurence

data Status = SActive | SDeleted deriving (Eq, Show)

instance Eq EventInfo where
   (EventInfo {_eventNumber=e1}) == (EventInfo {_eventNumber=e2}) = e1 == e2

instance Ord EventInfo where
   (EventInfo {_eventNumber=e1}) <= (EventInfo {_eventNumber=e2}) = e1 <= e2


-- * Rule

-- | Type of a rule function.
type Rule = Nomex ()
  
-- | An informationnal structure about a rule
data RuleInfo = RuleInfo { _rNumber      :: RuleNumber,       -- number of the rule (must be unique) TO CHECK
                           _rName        :: RuleName,         -- short name of the rule 
                           _rDescription :: String,           -- description of the rule
                           _rProposedBy  :: PlayerNumber,     -- player proposing the rule
                           _rRuleCode    :: Code,             -- code of the rule as a string
                           _rRule        :: Rule,             -- function representing the rule (interpreted from rRuleCode)
                           _rStatus      :: RuleStatus,       -- status of the rule
                           _rAssessedBy  :: Maybe RuleNumber} -- which rule accepted or rejected this rule
                           deriving (Typeable, Show)

instance Eq RuleInfo where
    (RuleInfo {_rNumber=r1}) == (RuleInfo {_rNumber=r2}) = r1 == r2

instance Ord RuleInfo where
     (RuleInfo {_rNumber=r1}) <= (RuleInfo {_rNumber=r2}) = r1 <= r2

-- | the status of a rule.
data RuleStatus = Active      -- Active rules forms the current Constitution
                | Pending     -- Proposed rules
                | Reject      -- Rejected rules
                deriving (Eq, Show, Typeable)
          
-- * Player

-- | informations on players
data PlayerInfo = PlayerInfo { _playerNumber :: PlayerNumber,
                               _playerName   :: String,
                               _playAs       :: Maybe PlayerNumber}
                               deriving (Eq, Typeable, Show)

instance Ord PlayerInfo where
   h <= g = (_playerNumber h) <= (_playerNumber g)

-- * Victory

data VictoryInfo = VictoryInfo { _vRuleNumber :: RuleNumber,
                                 _vCond :: NomexNE [PlayerNumber]}
                                 deriving (Show, Typeable)

partial :: String -> Nomex (Maybe a) -> Nomex a
partial s nm = do
   m <- nm
   case m of
      Just a -> return a
      Nothing -> throwError s

concatMapM        :: (Monad m) => (a -> m [b]) -> [a] -> m [b]
concatMapM f xs   =  liftM concat (mapM f xs)

$( makeLenses [''RuleInfo, ''PlayerInfo, ''EventInfo, ''SignalOccurence] )


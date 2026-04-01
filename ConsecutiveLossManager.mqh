//+------------------------------------------------------------------+
//| ConsecutiveLossManager.mqh                                       |
//| Manages streak detection, trade scoring, and dynamic sizing      |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      ""

// --- Global variable prefixes for persistence ---
string GetStreakPrefix() { return "CandleFailure_Streak_"; }

// Configuration (set from main EA)
double BaseTradeSizeMultiplier_Global = 1.0;
double MinTradeSizeMultiplier_Global = 0.5;
double StreakScorePenalty_Global = 0.5;
double TargetRR_Global = 2.0;

// --- Public functions (to be called from main EA) ---

void Streak_Init(double baseSizeMult, double minSizeMult, double streakPenalty, double targetRR) {
   BaseTradeSizeMultiplier_Global = baseSizeMult;
   MinTradeSizeMultiplier_Global = minSizeMult;
   StreakScorePenalty_Global = streakPenalty;
   TargetRR_Global = targetRR;
   
   string p = GetStreakPrefix();
   if(!GlobalVariableCheck(p + "consecutiveLosses")) {
      GlobalVariableSet(p + "consecutiveLosses", 0);
      GlobalVariableSet(p + "streakActive", 0.0);
      GlobalVariableSet(p + "virtualWins", 0);
   }
}

void Streak_OnTradeClose(double profit) {
   string p = GetStreakPrefix();
   int consecutiveLosses = (int)GlobalVariableGet(p + "consecutiveLosses");
   if(profit < 0) {
      consecutiveLosses++;
      GlobalVariableSet(p + "consecutiveLosses", consecutiveLosses);
      GlobalVariableSet(p + "streakActive", 1.0);
   } else {
      consecutiveLosses = 0;
      GlobalVariableSet(p + "consecutiveLosses", 0);
      GlobalVariableSet(p + "streakActive", 0.0);
      GlobalVariableSet(p + "virtualWins", 0);
   }
}

bool Streak_IsActive() {
   string p = GetStreakPrefix();
   return (GlobalVariableGet(p + "streakActive") != 0);
}

int Streak_GetConsecutiveLosses() {
   string p = GetStreakPrefix();
   return (int)GlobalVariableGet(p + "consecutiveLosses");
}

double Streak_ComputeScore(double atrRatio, double rr) {
   double atrScore = 1.0 - MathAbs(atrRatio - 1.0) / 2.0;
   atrScore = MathMax(atrScore, 0.2);
   double rrScore = MathMin(1.0, rr / TargetRR_Global);
   double baseScore = 0.5 * atrScore + 0.5 * rrScore;
   if(Streak_IsActive()) {
      int losses = Streak_GetConsecutiveLosses();
      double penalty = MathMin(StreakScorePenalty_Global, losses * 0.1);
      baseScore *= (1.0 - penalty);
   }
   return MathMax(baseScore, 0.0);
}

double Streak_GetSizeMultiplier() {
   if(!Streak_IsActive()) return BaseTradeSizeMultiplier_Global;
   int losses = Streak_GetConsecutiveLosses();
   double reduction = MathMin(1.0 - MinTradeSizeMultiplier_Global, losses * 0.15);
   double multiplier = BaseTradeSizeMultiplier_Global * (1.0 - reduction);
   return MathMax(multiplier, MinTradeSizeMultiplier_Global);
}

bool Streak_ShouldExecute(double score, double threshold) {
   double effectiveThreshold = threshold;
   if(Streak_IsActive()) effectiveThreshold += 0.1;
   return (score >= effectiveThreshold);
}

void Streak_UpdateVirtualWins(bool win) {
   string p = GetStreakPrefix();
   int virtualWins = (int)GlobalVariableGet(p + "virtualWins");
   if(win) virtualWins++;
   else virtualWins = MathMax(virtualWins - 1, 0);
   GlobalVariableSet(p + "virtualWins", virtualWins);
}

int Streak_GetVirtualWins() {
   string p = GetStreakPrefix();
   return (int)GlobalVariableGet(p + "virtualWins");
}

void Streak_ResetStreak() {
   string p = GetStreakPrefix();
   GlobalVariableSet(p + "streakActive", 0.0);
   GlobalVariableSet(p + "consecutiveLosses", 0);
   GlobalVariableSet(p + "virtualWins", 0);
}

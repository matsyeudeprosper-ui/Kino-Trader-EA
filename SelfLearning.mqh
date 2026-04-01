//+------------------------------------------------------------------+
//| SelfLearning.mqh                                                 |
//| Dynamically adjusts MinTradeScore based on historical outcomes   |
//| Also handles virtual win simulation and streak reset             |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      ""

// Configuration (set from main EA)
int LearningHistorySize_Global = 100;
double LearningSmoothingThreshold_Global = 0.3;
bool UseVirtualWins_Global = true;
int VirtualWinsRequired_Global = 1;

string GetLearningPrefix() { return "CandleFailure_Learn_"; }

// Use parallel arrays instead of struct
double scoreHistoryScores[];
bool   scoreHistoryIsWin[];
bool   scoreHistoryIsVirtual[];
int    scoreHistoryIdx = 0;
double dynamicMinScore = 0.6;
bool   learningReady = false;

void Learn_Init(int historySize, double smoothing, bool useVirtual, int virtualRequired) {
   LearningHistorySize_Global = historySize;
   LearningSmoothingThreshold_Global = smoothing;
   UseVirtualWins_Global = useVirtual;
   VirtualWinsRequired_Global = virtualRequired;
   
   string p = GetLearningPrefix();
   if(!GlobalVariableCheck(p + "dynamicMinScore")) {
      GlobalVariableSet(p + "dynamicMinScore", dynamicMinScore);
      GlobalVariableSet(p + "learningReady", 0);
   } else {
      dynamicMinScore = GlobalVariableGet(p + "dynamicMinScore");
      learningReady = (GlobalVariableGet(p + "learningReady") != 0);
   }
   ArrayResize(scoreHistoryScores, LearningHistorySize_Global);
   ArrayResize(scoreHistoryIsWin, LearningHistorySize_Global);
   ArrayResize(scoreHistoryIsVirtual, LearningHistorySize_Global);
   ArrayInitialize(scoreHistoryScores, 0.0);
   ArrayInitialize(scoreHistoryIsWin, false);
   ArrayInitialize(scoreHistoryIsVirtual, false);
   scoreHistoryIdx = 0;
}

void Learn_AddTrade(double score, bool isWin, bool isVirtual = false) {
   scoreHistoryScores[scoreHistoryIdx] = score;
   scoreHistoryIsWin[scoreHistoryIdx] = isWin;
   scoreHistoryIsVirtual[scoreHistoryIdx] = isVirtual;
   scoreHistoryIdx = (scoreHistoryIdx + 1) % LearningHistorySize_Global;
   if(scoreHistoryIdx >= 10) UpdateDynamicThreshold();
}

void UpdateDynamicThreshold() {
   double scores[];
   bool wins[];
   int count = 0;
   for(int i = 0; i < LearningHistorySize_Global; i++) {
      if(scoreHistoryIsVirtual[i]) continue;
      if(scoreHistoryScores[i] > 0) {
         ArrayResize(scores, count+1);
         ArrayResize(wins, count+1);
         scores[count] = scoreHistoryScores[i];
         wins[count] = scoreHistoryIsWin[i];
         count++;
      }
   }
   if(count < 10) return;
   double sortedScores[];
   ArrayCopy(sortedScores, scores);
   ArraySort(sortedScores);
   double uniqueScores[];
   int uniqueCount = 0;
   for(int i = 0; i < count; i++) {
      if(i == 0 || sortedScores[i] != sortedScores[i-1]) {
         ArrayResize(uniqueScores, uniqueCount+1);
         uniqueScores[uniqueCount] = sortedScores[i];
         uniqueCount++;
      }
   }
   double bestThreshold = dynamicMinScore;
   double bestWinRate = 0;
   for(int t = 0; t < uniqueCount; t++) {
      double thresh = uniqueScores[t];
      int winsAbove = 0, totalAbove = 0;
      for(int i = 0; i < count; i++) {
         if(scores[i] >= thresh) {
            totalAbove++;
            if(wins[i]) winsAbove++;
         }
      }
      if(totalAbove > 0) {
         double winRate = (double)winsAbove / totalAbove;
         if(winRate > bestWinRate) {
            bestWinRate = winRate;
            bestThreshold = thresh;
         }
      }
   }
   if(learningReady) {
      dynamicMinScore = LearningSmoothingThreshold_Global * bestThreshold + (1.0 - LearningSmoothingThreshold_Global) * dynamicMinScore;
   } else {
      dynamicMinScore = bestThreshold;
      learningReady = true;
   }
   dynamicMinScore = MathMax(0.4, MathMin(0.9, dynamicMinScore));
   string p = GetLearningPrefix();
   GlobalVariableSet(p + "dynamicMinScore", dynamicMinScore);
   GlobalVariableSet(p + "learningReady", learningReady ? 1.0 : 0.0);
   PrintFormat("Learning updated: dynamic MinTradeScore = %.3f (winRate=%.1f%%)", dynamicMinScore, bestWinRate*100);
}

double Learn_GetMinScore() { return dynamicMinScore; }

bool Learn_SimulateVirtualTrade(double score, double atrRatio, double rr) {
   if(!UseVirtualWins_Global) return false;
   bool isWin = (score > 0.7);
   if(isWin) PrintFormat("Virtual trade WIN (score=%.3f) - streak may be reset.", score);
   else PrintFormat("Virtual trade LOSS (score=%.3f) - streak continues.", score);
   Learn_AddTrade(score, isWin, true);
   return isWin;
}

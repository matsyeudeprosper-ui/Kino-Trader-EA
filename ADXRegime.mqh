//+------------------------------------------------------------------+
//| ADXRegime.mqh                                                    |
//| Market regime detection using ADX with directional filtering     |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      ""

// --- Market Regime Enum ---
enum MarketRegime {
   REGIME_STRONG_TREND,    // ADX > 25 and rising
   REGIME_WEAK_TREND,      // ADX between 20-25
   REGIME_RANGING          // ADX < 20
};

// --- Trend Direction Enum ---
enum TrendDirection {
   DIRECTION_NONE,         // No clear direction (ranging/weak trend)
   DIRECTION_BULLISH,      // +DI > -DI (uptrend)
   DIRECTION_BEARISH       // -DI > +DI (downtrend)
};

// --- Global Variables ---
int adxHandle = INVALID_HANDLE;
double currentADX = 0;
double previousADX = 0;
double currentPlusDI = 0;
double currentMinusDI = 0;
MarketRegime currentRegime = REGIME_STRONG_TREND;
TrendDirection currentDirection = DIRECTION_NONE;
bool adxInitialized = false;

// Configuration (set from main EA)
bool UseADXRegimeFilter_Global = true;
int ADXPeriod_Global = 14;
double ADXTrendThreshold_Global = 25.0;
double ADXRangingThreshold_Global = 20.0;
double RangingSizeReduction_Global = 0.5;
double WeakTrendSizeReduction_Global = 0.75;
double RangingScorePenalty_Global = 0.3;
double WeakTrendScorePenalty_Global = 0.1;

// Directional filtering configuration
bool UseDirectionalFilter_Global = true;
double CounterTrendSizeReduction = 0.25;
double CounterTrendScorePenalty = 0.5;
double AlignedTrendScoreBonus = 0.8;

// --- Persistent storage prefix ---
string GetADXPrefix() { return "CandleFailure_ADX_"; }

// --- Initialization ---
bool ADX_Init(ENUM_TIMEFRAMES timeframe, 
              bool useFilter, 
              int period, 
              double trendThresh, 
              double rangingThresh,
              double rangingReduction,
              double weakReduction,
              double rangingPenalty,
              double weakPenalty) {
   
   UseADXRegimeFilter_Global = useFilter;
   ADXPeriod_Global = period;
   ADXTrendThreshold_Global = trendThresh;
   ADXRangingThreshold_Global = rangingThresh;
   RangingSizeReduction_Global = rangingReduction;
   WeakTrendSizeReduction_Global = weakReduction;
   RangingScorePenalty_Global = rangingPenalty;
   WeakTrendScorePenalty_Global = weakPenalty;
   
   if(!UseADXRegimeFilter_Global) {
      adxInitialized = false;
      Print("ADX regime filter is disabled");
      return true;
   }
   
   // Initialize ADX handle (returns all 3 lines: ADX, +DI, -DI)
   adxHandle = iADX(_Symbol, timeframe, ADXPeriod_Global);
   if(adxHandle == INVALID_HANDLE) {
      Print("Failed to create ADX handle - disabling regime filter");
      UseADXRegimeFilter_Global = false;
      adxInitialized = false;
      return false;
   }
   
   // Direction detection is enabled by default since ADX handle gives all buffers
   UseDirectionalFilter_Global = true;
   Print("Directional filtering enabled (ADX with +/-DI)");
   
   // Load persisted regime if available
   string p = GetADXPrefix();
   if(GlobalVariableCheck(p + "currentRegime")) {
      currentRegime = (MarketRegime)(int)GlobalVariableGet(p + "currentRegime");
   }
   if(GlobalVariableCheck(p + "currentDirection")) {
      currentDirection = (TrendDirection)(int)GlobalVariableGet(p + "currentDirection");
   }
   
   adxInitialized = true;
   Print("ADX regime filter initialized successfully");
   return true;
}

// --- Get current market regime ---
MarketRegime ADX_GetRegime() {
   if(!UseADXRegimeFilter_Global || !adxInitialized) {
      return REGIME_STRONG_TREND;
   }
   
   double adx[2]; // Current and previous (buffer index 0 = ADX)
   if(CopyBuffer(adxHandle, 0, 0, 2, adx) < 2) {
      return REGIME_STRONG_TREND;
   }
   
   currentADX = adx[0];
   previousADX = adx[1];
   
   // Determine regime based on ADX value and trend
   if(currentADX > ADXTrendThreshold_Global) {
      if(currentADX > previousADX) {
         currentRegime = REGIME_STRONG_TREND;
      } else {
         currentRegime = REGIME_WEAK_TREND;
      }
   }
   else if(currentADX < ADXRangingThreshold_Global) {
      currentRegime = REGIME_RANGING;
   }
   else {
      currentRegime = REGIME_WEAK_TREND;
   }
   
   // Persist regime for recovery
   string p = GetADXPrefix();
   GlobalVariableSet(p + "currentRegime", (double)currentRegime);
   
   return currentRegime;
}

// --- Get current trend direction ---
TrendDirection ADX_GetDirection() {
   if(!UseADXRegimeFilter_Global || !adxInitialized) {
      return DIRECTION_NONE;
   }
   
   if(!UseDirectionalFilter_Global) {
      return DIRECTION_NONE;
   }
   
   double plusDI[1], minusDI[1];
   // Buffer 1 = +DI, Buffer 2 = -DI
   if(CopyBuffer(adxHandle, 1, 0, 1, plusDI) > 0 &&
      CopyBuffer(adxHandle, 2, 0, 1, minusDI) > 0) {
      currentPlusDI = plusDI[0];
      currentMinusDI = minusDI[0];
      
      // Determine direction with hysteresis (avoid noise)
      double diff = currentPlusDI - currentMinusDI;
      
      if(diff > 2.0) {  // +DI significantly higher
         currentDirection = DIRECTION_BULLISH;
      }
      else if(diff < -2.0) {  // -DI significantly higher
         currentDirection = DIRECTION_BEARISH;
      }
      else {
         // In weak trends, keep previous direction to avoid flipping
         if(currentRegime != REGIME_STRONG_TREND) {
            // Don't change direction in weak trends
         } else {
            currentDirection = DIRECTION_NONE;
         }
      }
   }
   
   // Persist direction for recovery
   string p = GetADXPrefix();
   GlobalVariableSet(p + "currentDirection", (double)currentDirection);
   
   return currentDirection;
}

// --- Get ADX value for display ---
double ADX_GetCurrentValue() {
   if(!UseADXRegimeFilter_Global || !adxInitialized) return 0;
   return currentADX;
}

// --- Get Plus DI value ---
double ADX_GetPlusDI() {
   if(!UseADXRegimeFilter_Global || !adxInitialized) return 0;
   return currentPlusDI;
}

// --- Get Minus DI value ---
double ADX_GetMinusDI() {
   if(!UseADXRegimeFilter_Global || !adxInitialized) return 0;
   return currentMinusDI;
}

// --- Get regime description string ---
string ADX_GetRegimeDescription() {
   if(!UseADXRegimeFilter_Global) return "FILTER DISABLED";
   
   MarketRegime regime = ADX_GetRegime();
   TrendDirection dir = ADX_GetDirection();
   string dirText = "";
   
   if(regime == REGIME_STRONG_TREND && UseDirectionalFilter_Global) {
      if(dir == DIRECTION_BULLISH) dirText = " ▲ BULLISH";
      else if(dir == DIRECTION_BEARISH) dirText = " ▼ BEARISH";
      else dirText = " (Direction Unclear)";
   }
   
   switch(regime) {
      case REGIME_STRONG_TREND:
         return StringFormat("STRONG TREND%s (ADX: %.1f, +DI: %.1f, -DI: %.1f)", 
                            dirText, currentADX, currentPlusDI, currentMinusDI);
      case REGIME_WEAK_TREND:
         return StringFormat("WEAK TREND (ADX: %.1f)", currentADX);
      case REGIME_RANGING:
         return StringFormat("RANGING (ADX: %.1f)", currentADX);
      default:
         return "UNKNOWN";
   }
}

// --- Get regime color for visualization ---
color ADX_GetRegimeColor() {
   MarketRegime regime = ADX_GetRegime();
   TrendDirection dir = ADX_GetDirection();
   
   if(regime == REGIME_STRONG_TREND && UseDirectionalFilter_Global) {
      if(dir == DIRECTION_BULLISH) return clrLimeGreen;
      if(dir == DIRECTION_BEARISH) return clrOrangeRed;
   }
   
   switch(regime) {
      case REGIME_STRONG_TREND:
         return clrGreen;
      case REGIME_WEAK_TREND:
         return clrYellow;
      case REGIME_RANGING:
         return clrRed;
      default:
         return clrGray;
   }
}

// --- Get size multiplier based on regime ---
double ADX_GetSizeMultiplier() {
   if(!UseADXRegimeFilter_Global || !adxInitialized) return 1.0;
   
   MarketRegime regime = ADX_GetRegime();
   switch(regime) {
      case REGIME_STRONG_TREND:
         return 1.0;
      case REGIME_WEAK_TREND:
         return WeakTrendSizeReduction_Global;
      case REGIME_RANGING:
         return RangingSizeReduction_Global;
      default:
         return 1.0;
   }
}

// --- Get direction-aware size multiplier ---
double ADX_GetDirectionalSizeMultiplier(int tradeDirection) {
   if(!UseADXRegimeFilter_Global || !adxInitialized) return 1.0;
   if(!UseDirectionalFilter_Global) return 1.0;
   
   MarketRegime regime = ADX_GetRegime();
   TrendDirection trendDir = ADX_GetDirection();
   
   // Only apply directional filtering in strong trends
   if(regime != REGIME_STRONG_TREND) {
      return 1.0;
   }
   
   // Check if trading with or against the trend
   bool tradingWithTrend = false;
   if(tradeDirection == 0) {
      tradingWithTrend = (trendDir == DIRECTION_BULLISH);
   } else {
      tradingWithTrend = (trendDir == DIRECTION_BEARISH);
   }
   
   if(tradingWithTrend) {
      return 1.0;
   } else if(trendDir != DIRECTION_NONE) {
      return CounterTrendSizeReduction;
   }
   
   return 1.0;
}

// --- Get score adjustment based on regime ---
double ADX_GetScoreAdjustment(double originalScore) {
   if(!UseADXRegimeFilter_Global || !adxInitialized) return originalScore;
   
   MarketRegime regime = ADX_GetRegime();
   switch(regime) {
      case REGIME_STRONG_TREND:
         return originalScore * 0.9;
      case REGIME_WEAK_TREND:
         return originalScore * (1.0 + WeakTrendScorePenalty_Global);
      case REGIME_RANGING:
         return originalScore * (1.0 + RangingScorePenalty_Global);
      default:
         return originalScore;
   }
}

// --- Get direction-aware score adjustment ---
double ADX_GetDirectionalScoreAdjustment(double originalScore, int tradeDirection) {
   if(!UseADXRegimeFilter_Global || !adxInitialized) return originalScore;
   if(!UseDirectionalFilter_Global) return originalScore;
   
   MarketRegime regime = ADX_GetRegime();
   TrendDirection trendDir = ADX_GetDirection();
   
   if(regime != REGIME_STRONG_TREND) {
      return originalScore;
   }
   
   bool tradingWithTrend = false;
   if(tradeDirection == 0) {
      tradingWithTrend = (trendDir == DIRECTION_BULLISH);
   } else {
      tradingWithTrend = (trendDir == DIRECTION_BEARISH);
   }
   
   if(tradingWithTrend) {
      return originalScore * AlignedTrendScoreBonus;
   } else if(trendDir != DIRECTION_NONE) {
      return originalScore * (1.0 + CounterTrendScorePenalty);
   }
   
   return originalScore;
}

// --- Get threshold adjustment for execution ---
double ADX_GetAdjustedThreshold(double baseThreshold) {
   if(!UseADXRegimeFilter_Global || !adxInitialized) return baseThreshold;
   
   MarketRegime regime = ADX_GetRegime();
   switch(regime) {
      case REGIME_STRONG_TREND:
         return baseThreshold * 0.9;
      case REGIME_WEAK_TREND:
         return baseThreshold * (1.0 + WeakTrendScorePenalty_Global);
      case REGIME_RANGING:
         return baseThreshold * (1.0 + RangingScorePenalty_Global);
      default:
         return baseThreshold;
   }
}

// --- Get direction-aware threshold adjustment ---
double ADX_GetDirectionalThreshold(double baseThreshold, int tradeDirection) {
   if(!UseADXRegimeFilter_Global || !adxInitialized) return baseThreshold;
   if(!UseDirectionalFilter_Global) return baseThreshold;
   
   MarketRegime regime = ADX_GetRegime();
   TrendDirection trendDir = ADX_GetDirection();
   
   if(regime != REGIME_STRONG_TREND) {
      return baseThreshold;
   }
   
   bool tradingWithTrend = false;
   if(tradeDirection == 0) {
      tradingWithTrend = (trendDir == DIRECTION_BULLISH);
   } else {
      tradingWithTrend = (trendDir == DIRECTION_BEARISH);
   }
   
   if(tradingWithTrend) {
      return baseThreshold * AlignedTrendScoreBonus;
   } else if(trendDir != DIRECTION_NONE) {
      return baseThreshold * (1.0 + CounterTrendScorePenalty);
   }
   
   return baseThreshold;
}

// --- Get complete multiplier (regime + direction) for position sizing ---
double ADX_GetCompleteSizeMultiplier(int tradeDirection) {
   double regimeMultiplier = ADX_GetSizeMultiplier();
   double directionMultiplier = ADX_GetDirectionalSizeMultiplier(tradeDirection);
   return regimeMultiplier * directionMultiplier;
}

// --- Get complete score adjustment (regime + direction) ---
double ADX_GetCompleteScoreAdjustment(double originalScore, int tradeDirection) {
   double regimeAdjusted = ADX_GetScoreAdjustment(originalScore);
   double directionAdjusted = ADX_GetDirectionalScoreAdjustment(regimeAdjusted, tradeDirection);
   return directionAdjusted;
}

// --- Get complete threshold adjustment (regime + direction) ---
double ADX_GetCompleteThreshold(double baseThreshold, int tradeDirection) {
   double regimeThreshold = ADX_GetAdjustedThreshold(baseThreshold);
   double directionThreshold = ADX_GetDirectionalThreshold(regimeThreshold, tradeDirection);
   return directionThreshold;
}

// --- Check if market is favorable for trading ---
bool ADX_IsFavorableForTrading() {
   if(!UseADXRegimeFilter_Global) return true;
   if(!adxInitialized) return true;
   return true;
}

// --- Check if specific trade direction is favorable ---
bool ADX_IsDirectionFavorable(int tradeDirection) {
   if(!UseADXRegimeFilter_Global) return true;
   if(!adxInitialized) return true;
   if(!UseDirectionalFilter_Global) return true;
   
   MarketRegime regime = ADX_GetRegime();
   TrendDirection trendDir = ADX_GetDirection();
   
   if(regime != REGIME_STRONG_TREND) {
      return true;
   }
   
   if(tradeDirection == 0) {
      return (trendDir == DIRECTION_BULLISH);
   } else {
      return (trendDir == DIRECTION_BEARISH);
   }
}

// --- Get regime for logging ---
string ADX_GetRegimeString() {
   MarketRegime regime = ADX_GetRegime();
   switch(regime) {
      case REGIME_STRONG_TREND: return "STRONG_TREND";
      case REGIME_WEAK_TREND: return "WEAK_TREND";
      case REGIME_RANGING: return "RANGING";
      default: return "UNKNOWN";
   }
}

// --- Get direction string for logging ---
string ADX_GetDirectionString() {
   TrendDirection dir = ADX_GetDirection();
   switch(dir) {
      case DIRECTION_BULLISH: return "BULLISH";
      case DIRECTION_BEARISH: return "BEARISH";
      default: return "NONE";
   }
}

// --- Cleanup ---
void ADX_Cleanup() {
   if(adxHandle != INVALID_HANDLE) {
      IndicatorRelease(adxHandle);
      adxHandle = INVALID_HANDLE;
   }
}

// --- Draw ADX info on chart ---
void ADX_DrawInfo() {
   if(!UseADXRegimeFilter_Global) return;
   if(!adxInitialized) return;
   
   string regimeText = ADX_GetRegimeDescription();
   color regimeColor = ADX_GetRegimeColor();
   
   if(ObjectFind(0, "ADX_Regime_Label") < 0) {
      ObjectCreate(0, "ADX_Regime_Label", OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, "ADX_Regime_Label", OBJPROP_CORNER, 1);
      ObjectSetInteger(0, "ADX_Regime_Label", OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, "ADX_Regime_Label", OBJPROP_YDISTANCE, 30);
      ObjectSetInteger(0, "ADX_Regime_Label", OBJPROP_FONTSIZE, 10);
   }
   
   ObjectSetString(0, "ADX_Regime_Label", OBJPROP_TEXT, regimeText);
   ObjectSetInteger(0, "ADX_Regime_Label", OBJPROP_COLOR, regimeColor);
   
   if(UseDirectionalFilter_Global) {
      string diText = StringFormat("+DI: %.1f  -DI: %.1f", currentPlusDI, currentMinusDI);
      if(ObjectFind(0, "ADX_DI_Label") < 0) {
         ObjectCreate(0, "ADX_DI_Label", OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, "ADX_DI_Label", OBJPROP_CORNER, 1);
         ObjectSetInteger(0, "ADX_DI_Label", OBJPROP_XDISTANCE, 10);
         ObjectSetInteger(0, "ADX_DI_Label", OBJPROP_YDISTANCE, 50);
         ObjectSetInteger(0, "ADX_DI_Label", OBJPROP_FONTSIZE, 9);
      }
      ObjectSetString(0, "ADX_DI_Label", OBJPROP_TEXT, diText);
      ObjectSetInteger(0, "ADX_DI_Label", OBJPROP_COLOR, clrGray);
   }
}

// --- Remove ADX info ---
void ADX_RemoveInfo() {
   ObjectDelete(0, "ADX_Regime_Label");
   ObjectDelete(0, "ADX_DI_Label");
}

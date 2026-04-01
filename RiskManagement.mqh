//+------------------------------------------------------------------+
//| RiskManagement.mqh                                               |
//| Risk management and position sizing functions for EA             |
//| Includes: Position sizing, ATR statistics, Order placement,      |
//| Dynamic SL based on ATR/ADX, Smart Breakeven, and Trailing Stop |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      ""

//+------------------------------------------------------------------+
//| Get current ATR ratio                                            |
//+------------------------------------------------------------------+
double GetCurrentATRRatio() {
   if(!atrHandlesValid) return 1.0;
   double shortATR[1], longATR[1];
   if(CopyBuffer(atrShortHandle, 0, 0, 1, shortATR) > 0 &&
      CopyBuffer(atrLongHandle, 0, 0, 1, longATR) > 0 && longATR[0] > 0) {
      return shortATR[0] / longATR[0];
   }
   return 1.0;
}

//+------------------------------------------------------------------+
//| Normalize lot size according to broker limits                    |
//+------------------------------------------------------------------+
double NormalizeLotSize(double lot) {
   symbolMinLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   symbolMaxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   symbolLotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(symbolLotStep >= 0.1) symbolDigits = 1;
   else if(symbolLotStep >= 0.01) symbolDigits = 2;
   else if(symbolLotStep >= 0.001) symbolDigits = 3;
   else if(symbolLotStep >= 0.0001) symbolDigits = 4;
   else symbolDigits = 2;
   
   if(lot < symbolMinLot) lot = symbolMinLot;
   if(lot > symbolMaxLot) lot = symbolMaxLot;
   
   if(symbolLotStep > 0) {
      lot = MathRound(lot / symbolLotStep) * symbolLotStep;
   }
   
   lot = NormalizeDouble(lot, symbolDigits);
   return lot;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage                      |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPoints) {
   if(LotSizeFixed > 0) {
      double lot = LotSizeFixed;
      lot = NormalizeLotSize(lot);
      return lot;
   }
   
   double account = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = account * RiskPercent / 100.0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ticks = slPoints * point / tickSize;
   double riskPerLot = ticks * tickValue;
   
   if(riskPerLot <= 0) return 0;
   
   double lot = riskMoney / riskPerLot;
   lot = NormalizeLotSize(lot);
   
   return lot;
}

//+------------------------------------------------------------------+
//| Adjust lot size for available margin                            |
//+------------------------------------------------------------------+
double AdjustLotForMargin(double requestedLot, double price, int direction) {
   double lot = requestedLot;
   lot = NormalizeLotSize(lot);
   
   ENUM_ORDER_TYPE orderType = (direction == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginRequired = 0;
   
   while(lot >= symbolMinLot) {
      if(OrderCalcMargin(orderType, _Symbol, lot, price, marginRequired)) {
         if(marginRequired <= freeMargin) {
            return lot;
         }
      }
      lot = lot - symbolLotStep;
      lot = NormalizeLotSize(lot);
      if(lot < symbolMinLot) break;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Validate stop loss and take profit levels                        |
//+------------------------------------------------------------------+
bool ValidateStops(int direction, double sl, double tp) {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double spread = (ask - bid) / point;
   double bufferPoints = spread + 2.0;
   
   sl = MathRound(sl / tickSize) * tickSize;
   tp = MathRound(tp / tickSize) * tickSize;
   
   if(direction == 0) {
      if(sl >= bid - bufferPoints * point) return false;
      if(tp <= ask + bufferPoints * point) return false;
      double slDistance = (bid - sl) / point;
      if(slDistance < stopsLevel - 1e-6) return false;
   } else {
      if(sl <= ask + bufferPoints * point) return false;
      if(tp >= bid - bufferPoints * point) return false;
      double slDistance = (sl - ask) / point;
      if(slDistance < stopsLevel - 1e-6) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Save trade data to Global Variables                              |
//+------------------------------------------------------------------+
void SaveTradeData(ulong ticket, double atrRatio, double rr, double score) {
   string prefix = GetPrefix() + "trade_";
   GlobalVariableSet(prefix + (string)ticket + "_atr", atrRatio);
   GlobalVariableSet(prefix + (string)ticket + "_rr", rr);
   GlobalVariableSet(prefix + (string)ticket + "_score", score);
   GlobalVariableSet(prefix + (string)ticket + "_openTime", (double)TimeCurrent());
}

//+------------------------------------------------------------------+
//| Load trade data from Global Variables                            |
//+------------------------------------------------------------------+
bool LoadTradeData(ulong ticket, double &atrRatio, double &rr, double &score) {
   string prefix = GetPrefix() + "trade_";
   string nameATR = prefix + (string)ticket + "_atr";
   string nameRR = prefix + (string)ticket + "_rr";
   string nameScore = prefix + (string)ticket + "_score";
   if(GlobalVariableCheck(nameATR) && GlobalVariableCheck(nameRR) && GlobalVariableCheck(nameScore)) {
      atrRatio = GlobalVariableGet(nameATR);
      rr = GlobalVariableGet(nameRR);
      score = GlobalVariableGet(nameScore);
      GlobalVariableDel(nameATR);
      GlobalVariableDel(nameRR);
      GlobalVariableDel(nameScore);
      GlobalVariableDel(prefix + (string)ticket + "_openTime");
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calculate monetary risk for a trade                              |
//+------------------------------------------------------------------+
double CalculateMonetaryRisk(double slPoints, double lot) {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ticks = slPoints * point / tickSize;
   return ticks * tickValue * lot;
}

//+------------------------------------------------------------------+
//| Record completed trade for learning                              |
//+------------------------------------------------------------------+
void RecordTrade(ulong ticket, double profit, bool isWin) {
   double atrRatio, rr, score;
   if(!LoadTradeData(ticket, atrRatio, rr, score)) return;
   
   int size = ArraySize(tradeHistory);
   ArrayResize(tradeHistory, size + 1);
   tradeHistory[size].ticket = ticket;
   tradeHistory[size].atrRatio = atrRatio;
   tradeHistory[size].rr = rr;
   tradeHistory[size].profit = profit;
   tradeHistory[size].isWin = isWin;
   tradeHistory[size].closeTime = TimeCurrent();
   tradeCount++;
   
   if(tradeCount >= MinTradesToLearn) {
      if(UseATRFilter) {
         double binEdges[] = {0.5, 0.8, 1.0, 1.2, 1.5, 2.0};
         int binCount = 5;
         int winCount[], totalCount[];
         ArrayResize(winCount, binCount);
         ArrayResize(totalCount, binCount);
         ArrayInitialize(winCount, 0);
         ArrayInitialize(totalCount, 0);
         
         int histSize = ArraySize(tradeHistory);
         for(int i = 0; i < histSize; i++) {
            double ratio = tradeHistory[i].atrRatio;
            if(ratio < 0.5) ratio = 0.5;
            if(ratio > 2.0) ratio = 2.0;
            for(int b = 0; b < binCount; b++) {
               if(ratio >= binEdges[b] && ratio < binEdges[b+1]) {
                  totalCount[b]++;
                  if(tradeHistory[i].isWin) winCount[b]++;
                  break;
               }
            }
         }
         
         int bestBin = -1;
         double bestWinRate = 0;
         for(int b = 0; b < binCount; b++) {
            if(totalCount[b] >= 3) {
               double winRate = (double)winCount[b] / totalCount[b];
               if(winRate > bestWinRate) {
                  bestWinRate = winRate;
                  bestBin = b;
               }
            }
         }
         
         if(bestBin >= 0) {
            double newMin = binEdges[bestBin];
            double newMax = binEdges[bestBin+1];
            newMin = MathMax(newMin, 0.5);
            newMax = MathMin(newMax, 2.0);
            
            if(learningInitialized) {
               learnedMinATR = LearningSmoothing * newMin + (1.0 - LearningSmoothing) * learnedMinATR;
               learnedMaxATR = LearningSmoothing * newMax + (1.0 - LearningSmoothing) * learnedMaxATR;
            } else {
               learnedMinATR = newMin;
               learnedMaxATR = newMax;
               learningInitialized = true;
            }
            SaveState();
         }
      }
   }
   
   if(ArraySize(tradeHistory) > 200) {
      int toDelete = ArraySize(tradeHistory) - 200;
      ArrayRemove(tradeHistory, 0, toDelete);
   }
}

//+------------------------------------------------------------------+
//| Initialize ATR indicator handles                                 |
//+------------------------------------------------------------------+
void InitATRHandles() {
   atrShortHandle = iATR(_Symbol, TF, ATRShortPeriod);
   atrLongHandle = iATR(_Symbol, TF, ATROutPeriod);
   if(atrShortHandle == INVALID_HANDLE || atrLongHandle == INVALID_HANDLE) {
      atrHandlesValid = false;
   } else {
      ArrayResize(atrRatioHistory, ATRHistorySize);
      ArrayInitialize(atrRatioHistory, 0.0);
      atrHistoryIdx = 0;
      atrStatsReady = false;
      atrHandlesValid = true;
   }
}

//+------------------------------------------------------------------+
//| Update ATR statistics                                            |
//+------------------------------------------------------------------+
void UpdateATRStats() {
   if(!UseATRFilter) return;
   if(!atrHandlesValid) return;
   
   double shortATR[1], longATR[1];
   if(CopyBuffer(atrShortHandle, 0, 0, 1, shortATR) <= 0 ||
      CopyBuffer(atrLongHandle, 0, 0, 1, longATR) <= 0) return;
   if(longATR[0] <= 0) return;
   
   double ratio = shortATR[0] / longATR[0];
   atrRatioHistory[atrHistoryIdx] = ratio;
   atrHistoryIdx = (atrHistoryIdx + 1) % ATRHistorySize;
   
   double sum = 0, sumSq = 0;
   int count = 0;
   for(int i = 0; i < ATRHistorySize; i++) {
      if(atrRatioHistory[i] > 0) {
         sum += atrRatioHistory[i];
         sumSq += atrRatioHistory[i] * atrRatioHistory[i];
         count++;
      }
   }
   if(count > 10) {
      double mean = sum / count;
      double variance = (sumSq / count) - (mean * mean);
      double std = MathSqrt(MathMax(variance, 0.0));
      if(atrStatsReady) {
         atrMean = ATRLearningAlpha * mean + (1.0 - ATRLearningAlpha) * atrMean;
         atrStd = ATRLearningAlpha * std + (1.0 - ATRLearningAlpha) * atrStd;
      } else {
         atrMean = mean;
         atrStd = std;
         atrStatsReady = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Check if ATR ratio is valid for trading                          |
//+------------------------------------------------------------------+
bool IsATRRatioValid() {
   if(!UseATRFilter) return true;
   if(!atrHandlesValid) return true;
   if(!atrStatsReady) return true;
   
   double shortATR[1], longATR[1];
   if(CopyBuffer(atrShortHandle, 0, 0, 1, shortATR) <= 0 ||
      CopyBuffer(atrLongHandle, 0, 0, 1, longATR) <= 0) return true;
   if(longATR[0] <= 0) return true;
   
   double ratio = shortATR[0] / longATR[0];
   double minRatio, maxRatio;
   if(learningInitialized && tradeCount >= MinTradesToLearn) {
      minRatio = learnedMinATR;
      maxRatio = learnedMaxATR;
   } else {
      minRatio = atrMean - ATRSensitivity * atrStd;
      maxRatio = atrMean + ATRSensitivity * atrStd;
      minRatio = MathMax(minRatio, 0.5);
      maxRatio = MathMin(maxRatio, 2.0);
   }
   
   return (ratio >= minRatio && ratio <= maxRatio);
}

//+------------------------------------------------------------------+
//| Get error description                                            |
//+------------------------------------------------------------------+
string ErrorDescription(int error) {
   switch(error) {
      case 4756: return "Invalid stops - SL cannot be placed at or beyond current price";
      case 10004: return "Invalid stops (too close)";
      case 10017: return "Invalid stops (no price)";
      case 10021: return "Invalid stops (market closed)";
      case 10025: return "Invalid stops (frozen)";
      case 10028: return "Invalid stops (no change)";
      default: return "Unknown error";
   }
}

//+------------------------------------------------------------------+
//| Calculate Dynamic Stop Loss and Take Profit based on ATR/ADX    |
//+------------------------------------------------------------------+
void CalculateDynamicLevels(double entry, int direction, double &sl, double &tp, 
                            double range, double point) {
   double atrBuffer[];
   double adxBuffer[];
   
   ArraySetAsSeries(atrBuffer, true);
   ArraySetAsSeries(adxBuffer, true);
   
   int atrHandle = iATR(_Symbol, TF, 14);
   int adxHandle = iADX(_Symbol, TF, ADXPeriod);
   
   if(atrHandle == INVALID_HANDLE || adxHandle == INVALID_HANDLE) {
      if(direction == 0) {
         sl = entry - range;
         tp = entry + (range * TargetRR);
      } else {
         sl = entry + range;
         tp = entry - (range * TargetRR);
      }
      if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
      if(adxHandle != INVALID_HANDLE) IndicatorRelease(adxHandle);
      return;
   }
   
   CopyBuffer(atrHandle, 0, 0, 1, atrBuffer);
   CopyBuffer(adxHandle, 0, 0, 1, adxBuffer);
   
   double atr = atrBuffer[0];
   double adx = adxBuffer[0];
   
   double minADX = 15.0;
   double maxADX = 50.0;
   double minScale = 0.7;
   double maxScale = 1.5;
   
   double clampedADX = adx;
   if(clampedADX < minADX) clampedADX = minADX;
   if(clampedADX > maxADX) clampedADX = maxADX;
   
   double adxScale = minScale + (clampedADX - minADX) / (maxADX - minADX) * (maxScale - minScale);
   
   double baseSLDistance = atr * 0.5;
   double finalSLDistance = baseSLDistance * adxScale;
   finalSLDistance = MathMax(finalSLDistance, range);
   
   if(direction == 0) {
      sl = entry - finalSLDistance;
      tp = entry + (finalSLDistance * TargetRR);
   } else {
      sl = entry + finalSLDistance;
      tp = entry - (finalSLDistance * TargetRR);
   }
   
   IndicatorRelease(atrHandle);
   IndicatorRelease(adxHandle);
   
   PrintFormat("Dynamic SL: ATR=%.1f, ADX=%.1f, Scale=%.2f, Risk=%.1f pips, Reward=%.1f pips",
               atr/point, adx, adxScale, finalSLDistance/point, (finalSLDistance*TargetRR)/point);
}

//+------------------------------------------------------------------+
//| Apply Breakeven with Buffer - COMPLETE FIX                      |
//+------------------------------------------------------------------+
void ApplyBreakevenWithBuffer(double entry, int type, double tp, double buffer) {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int safeMinStops = (stopsLevel > 0) ? stopsLevel : 10;
   
   double newSL;
   double currentPrice;
   
   if(type == POSITION_TYPE_BUY) {
      currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      newSL = entry + buffer;
      
      if(newSL >= currentPrice) {
         PrintFormat("⚠️ BUY SL would be above price! Using price - min buffer");
         newSL = currentPrice - (safeMinStops * point);
      }
   } else {
      currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      newSL = entry - buffer;
      
      if(newSL <= currentPrice) {
         PrintFormat("⚠️ SELL SL would be below price! Using price + min buffer");
         newSL = currentPrice + (safeMinStops * point);
      }
   }
   
   bool validSL = false;
   if(type == POSITION_TYPE_BUY) {
      validSL = (newSL < currentPrice);
   } else {
      validSL = (newSL > currentPrice);
   }
   
   double stopDistance = (type == POSITION_TYPE_BUY) ?
                         (currentPrice - newSL) / point : 
                         (newSL - currentPrice) / point;
   
   PrintFormat("BREAKEVEN: Type=%s, Entry=%.2f, NewSL=%.2f, Price=%.2f, Dist=%.1f pips, MinReq=%d, Valid=%s",
               type==POSITION_TYPE_BUY?"BUY":"SELL", entry, newSL, currentPrice, 
               stopDistance, safeMinStops, validSL?"YES":"NO");
   
   if(validSL && stopDistance >= safeMinStops) {
      if(trade.PositionModify(openTicket, newSL, tp)) {
         breakevenApplied = true;
         PrintFormat("✅ Breakeven SUCCESS: SL moved to %.5f", newSL);
      } else {
         int error = GetLastError();
         PrintFormat("❌ Breakeven FAILED: Error %d - %s", error, ErrorDescription(error));
         PrintFormat("   Attempted: SL=%.5f, TP=%.5f, Entry=%.5f", newSL, tp, entry);
      }
   } else {
      PrintFormat("❌ Breakeven SKIPPED: %s", 
                  !validSL ? "SL on wrong side of price" : 
                  StringFormat("Distance %.1f pips < Required %d pips", stopDistance, safeMinStops));
   }
}

//+------------------------------------------------------------------+
//| Apply Standard Breakeven (Fallback)                             |
//+------------------------------------------------------------------+
void ApplyBreakeven(double entry, int type, double tp) {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int safeMinStops = (stopsLevel > 0) ? stopsLevel : 10;
   
   double newSL = entry;
   double currentPrice;
   
   if(type == POSITION_TYPE_BUY) {
      currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   } else {
      currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }
   
   double stopDistance = (type == POSITION_TYPE_BUY) ?
                         fabs(currentPrice - newSL) : 
                         fabs(newSL - currentPrice);
   
   if(stopDistance / point >= safeMinStops) {
      if(trade.PositionModify(openTicket, newSL, tp)) {
         breakevenApplied = true;
         Print("Breakeven applied (fallback)");
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Trailing Stop                                             |
//+------------------------------------------------------------------+
void ManageTrailingStop() {
   if(openTicket == 0) return;
   if(!PositionSelectByTicket(openTicket)) return;
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int type = (int)PositionGetInteger(POSITION_TYPE);
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   double currentPrice;
   
   if(type == POSITION_TYPE_BUY) {
      currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   } else {
      currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }
   
   double profitPips = (type == POSITION_TYPE_BUY) ? 
                       (currentPrice - entry) / point : 
                       (entry - currentPrice) / point;
   
   double riskPips = (type == POSITION_TYPE_BUY) ? 
                     (entry - currentSL) / point : 
                     (currentSL - entry) / point;
   
   if(profitPips < riskPips * 1.2) return;
   
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   int atrHandle = iATR(_Symbol, TF, 14);
   double atr = 0;
   
   if(atrHandle != INVALID_HANDLE) {
      CopyBuffer(atrHandle, 0, 0, 1, atrBuffer);
      atr = atrBuffer[0];
      IndicatorRelease(atrHandle);
   } else {
      atr = riskPips * point;
   }
   
   double trailDistance = atr * 0.6;
   double newSL;
   double stopDistance;
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int safeMinStops = (stopsLevel > 0) ? stopsLevel : 10;
   
   if(type == POSITION_TYPE_BUY) {
      newSL = currentPrice - trailDistance;
      if(newSL > currentSL) {
         stopDistance = (currentPrice - newSL) / point;
         if(stopDistance >= safeMinStops) {
            if(trade.PositionModify(openTicket, newSL, currentTP)) {
               double lockedProfit = (newSL - entry) / point;
               PrintFormat("Trailing stop moved: BUY SL=%.5f (%.1f pips profit locked)", 
                           newSL, lockedProfit);
            } else {
               int error = GetLastError();
               PrintFormat("Trailing stop FAILED: BUY Error %d - %s", error, ErrorDescription(error));
            }
         }
      }
   } else {
      newSL = currentPrice + trailDistance;
      if(newSL < currentSL) {
         stopDistance = (newSL - currentPrice) / point;
         if(stopDistance >= safeMinStops) {
            if(trade.PositionModify(openTicket, newSL, currentTP)) {
               double lockedProfit = (entry - newSL) / point;
               PrintFormat("Trailing stop moved: SELL SL=%.5f (%.1f pips profit locked)", 
                           newSL, lockedProfit);
            } else {
               int error = GetLastError();
               PrintFormat("Trailing stop FAILED: SELL Error %d - %s", error, ErrorDescription(error));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Smart Breakeven Management                                      |
//+------------------------------------------------------------------+
void ManageSmartBreakeven() {
   if(openTicket == 0) return;
   if(!PositionSelectByTicket(openTicket)) return;
   
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   int type = (int)PositionGetInteger(POSITION_TYPE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double currentPrice;
   double profitPips;
   
   if(type == POSITION_TYPE_BUY) {
      currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      profitPips = (currentPrice - entry) / point;
   } else {
      currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      profitPips = (entry - currentPrice) / point;
   }
   
   double originalRiskPips = (type == POSITION_TYPE_BUY) ? 
                             (entry - currentSL) / point : 
                             (currentSL - entry) / point;
   
   PrintFormat("Position Status: Type=%s, Entry=%.2f, CurrentPrice=%.2f, Profit=%.1f pips, Risk=%.1f pips",
               type==POSITION_TYPE_BUY?"BUY":"SELL", entry, currentPrice, profitPips, originalRiskPips);
   
   if(profitPips <= 0) return;
   
   if(!breakevenApplied) {
      double atrBuffer[];
      double adxBuffer[];
      ArraySetAsSeries(atrBuffer, true);
      ArraySetAsSeries(adxBuffer, true);
      
      int atrHandle = iATR(_Symbol, TF, 14);
      int adxHandle = iADX(_Symbol, TF, ADXPeriod);
      double atr = 0;
      double adx = 0;
      
      if(atrHandle != INVALID_HANDLE && adxHandle != INVALID_HANDLE) {
         CopyBuffer(atrHandle, 0, 0, 1, atrBuffer);
         CopyBuffer(adxHandle, 0, 0, 1, adxBuffer);
         atr = atrBuffer[0];
         adx = adxBuffer[0];
         IndicatorRelease(atrHandle);
         IndicatorRelease(adxHandle);
      } else {
         atr = originalRiskPips * point;
         adx = 25;
         if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
         if(adxHandle != INVALID_HANDLE) IndicatorRelease(adxHandle);
      }
      
      double atrPips = atr / point;
      double beThreshold;
      
      if(adx > ADXTrendThreshold * 1.5) {
         beThreshold = atrPips * 1.0;
      } else if(adx > ADXTrendThreshold) {
         beThreshold = atrPips * 0.7;
      } else if(adx < ADXRangingThreshold) {
         beThreshold = atrPips * 0.4;
      } else {
         beThreshold = atrPips * 0.5;
      }
      
      PrintFormat("Smart BE Check: Profit=%.1f pips, Threshold=%.1f pips, ADX=%.1f, ATR=%.1f",
                  profitPips, beThreshold, adx, atrPips);
      
      if(profitPips >= beThreshold) {
         double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - 
                         SymbolInfoDouble(_Symbol, SYMBOL_BID)) / point;
         double buffer = MathMax(point * 5, spread * 2);
         ApplyBreakevenWithBuffer(entry, type, currentTP, buffer);
      }
   }
   
   if(breakevenApplied) {
      ManageTrailingStop();
   }
}

//+------------------------------------------------------------------+
//| Main ManageBreakeven function (called from EA)                  |
//+------------------------------------------------------------------+
void ManageBreakeven() {
   ManageSmartBreakeven();
}

//+------------------------------------------------------------------+
//| Place market order with risk management                          |
//+------------------------------------------------------------------+
bool PlaceMarketOrder(int direction, double sl, double tp, double slPoints, double tradeScore) {
   double entry = (direction == 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStopPoints = (stopsLevel > 0) ? stopsLevel : 10;
   
   double range = (direction == 0) ? 
                  (pendingBuyEntry - pendingBuySL) : 
                  (pendingSellSL - pendingSellEntry);
   
   double dynamicSL, dynamicTP;
   CalculateDynamicLevels(entry, direction, dynamicSL, dynamicTP, range, point);
   
   double originalRisk = fabs(sl - entry) / point;
   double dynamicRisk = fabs(dynamicSL - entry) / point;
   
   if(dynamicRisk <= originalRisk * 2.0 && dynamicRisk >= minStopPoints) {
      sl = dynamicSL;
      tp = dynamicTP;
      PrintFormat("Using Dynamic SL: Risk=%.1f pips, Reward=%.1f pips", 
                  dynamicRisk, dynamicRisk * TargetRR);
   } else {
      PrintFormat("Using Original SL: Risk=%.1f pips", originalRisk);
   }
   
   // Safety check for SL direction
   if(direction == 0) {
      if(sl >= entry) {
         Print("ERROR: BUY SL above entry! Correcting...");
         sl = entry - MathMax(minStopPoints, 10) * point;
      }
   } else {
      if(sl <= entry) {
         Print("ERROR: SELL SL below entry! Correcting...");
         sl = entry + MathMax(minStopPoints, 10) * point;
      }
   }
   
   double desiredDistPoints = fabs(sl - entry) / point;
   if(desiredDistPoints < minStopPoints - 1e-6) {
      if(direction == 0) {
         sl = entry - minStopPoints * point;
      } else {
         sl = entry + minStopPoints * point;
      }
      desiredDistPoints = minStopPoints;
      if(direction == 0) {
         tp = entry + (desiredDistPoints * TargetRR) * point;
      } else {
         tp = entry - (desiredDistPoints * TargetRR) * point;
      }
   }
   
   double lot = (LotSizeFixed > 0) ? LotSizeFixed : CalculateLotSize(desiredDistPoints);
   if(lot <= 0) return false;
   
   double streakMultiplier = Streak_GetSizeMultiplier();
   lot *= streakMultiplier;
   
   double completeMultiplier = ADX_GetCompleteSizeMultiplier(direction);
   lot *= completeMultiplier;
   
   lot = AdjustLotForMargin(lot, entry, direction);
   lot = NormalizeLotSize(lot);
   
   if(lot <= 0) return false;
   
   double finalDist = fabs(sl - entry) / point;
   if(finalDist < minStopPoints - 1e-6) return false;
   
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   sl = MathRound(sl / tickSize) * tickSize;
   tp = MathRound(tp / tickSize) * tickSize;
   
   if(!ValidateStops(direction, sl, tp)) return false;
   if(MathAbs(sl - entry) < point * 0.5) return false;
   
   PrintFormat("Placing order: %s %.3f lots at %f, SL=%f (%d pips), TP=%f (%d pips)", 
               (direction==0?"BUY":"SELL"), lot, entry, sl, (int)(fabs(sl-entry)/point),
               tp, (int)(fabs(tp-entry)/point));
   
   for(int retry = 0; retry < MaxRetries; retry++) {
      ResetLastError();
      bool success = false;
      if(direction == 0) {
         success = trade.Buy(lot, _Symbol, 0.0, sl, tp);
      } else {
         success = trade.Sell(lot, _Symbol, 0.0, sl, tp);
      }
      
      if(success) {
         originalTP = tp;
         double atrRatio = GetCurrentATRRatio();
         SaveTradeData(trade.ResultOrder(), atrRatio, TargetRR, tradeScore);
         return true;
      }
      int err = GetLastError();
      if(err == 10004 || err == 10017) { Sleep(100); continue; }
      Print("Order failed with error: ", err);
      return false;
   }
   return false;
}

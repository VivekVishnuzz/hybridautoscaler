"""
Enhanced Reactive Autoscaler (RPS-based) with Production Features

Improvements:
1. Cooldown period to prevent flapping
2. Exponential moving average (EMA) for smooth RPS
3. Hysteresis (different thresholds for scale-up vs scale-down)
4. Configurable parameters
5. Better logging and metrics
"""

import pandas as pd
import time
from dataclasses import dataclass
from typing import Dict, List, Tuple
from collections import defaultdict

# ==================== CONFIGURATION ====================
CSV_PATH = "microservice_interactions_3hours.csv"
CONTROL_INTERVAL = 30  # seconds between control decisions
OUTPUT_CSV = "enhanced_reactive_output.csv"

# Scaling parameters
COOLDOWN_PERIOD = 60  # seconds to wait between scaling actions
EMA_ALPHA = 0.7  # weight for exponential moving average (0.7 = 70% current, 30% history)
MIN_REPLICAS = 1
MAX_REPLICAS = 10

# RPS Thresholds with Hysteresis
# Format: (scale_up_threshold, scale_down_threshold)
RPS_THRESHOLDS = {
    1: (10, 0),      # 1 replica: scale up at 10 RPS, never scale down (min)
    2: (30, 8),      # 2 replicas: scale up at 30 RPS, scale down at 8 RPS
    3: (60, 25),     # 3 replicas: scale up at 60 RPS, scale down at 25 RPS
    4: (100, 50),    # 4 replicas: scale up at 100 RPS, scale down at 50 RPS
    5: (float('inf'), 90)  # 5 replicas: never scale up (max), scale down at 90 RPS
}

# ==================== DATA STRUCTURES ====================
@dataclass
class ServiceState:
    """Track state for each service"""
    current_replicas: int = 1
    raw_rps: float = 0.0
    smoothed_rps: float = 0.0
    last_scale_time: int = 0
    scale_history: List[Tuple[int, int, float, str]] = None  # (time, replicas, rps, reason)
    
    def __post_init__(self):
        if self.scale_history is None:
            self.scale_history = []


# ==================== SCALING LOGIC ====================
def update_smoothed_rps(state: ServiceState, new_rps: float) -> float:
    """
    Calculate exponential moving average of RPS
    Formula: EMA = α * current + (1-α) * previous
    """
    if state.smoothed_rps == 0.0:
        # First data point, no history
        state.smoothed_rps = new_rps
    else:
        state.smoothed_rps = EMA_ALPHA * new_rps + (1 - EMA_ALPHA) * state.smoothed_rps
    
    state.raw_rps = new_rps
    return state.smoothed_rps


def desired_replicas_with_hysteresis(current_replicas: int, smoothed_rps: float) -> Tuple[int, str]:
    """
    Determine desired replicas using hysteresis to prevent flapping
    
    Returns: (desired_replicas, reason)
    """
    scale_up_threshold, scale_down_threshold = RPS_THRESHOLDS[current_replicas]
    
    # Check if we should scale UP
    if smoothed_rps >= scale_up_threshold and current_replicas < MAX_REPLICAS:
        # Find the right replica count
        for replicas in range(current_replicas + 1, MAX_REPLICAS + 1):
            up_thresh, _ = RPS_THRESHOLDS[replicas]
            if smoothed_rps < up_thresh:
                return replicas, f"RPS {smoothed_rps:.1f} >= {scale_up_threshold:.1f} (scale-up threshold)"
        return MAX_REPLICAS, f"RPS {smoothed_rps:.1f} exceeds all thresholds"
    
    # Check if we should scale DOWN
    elif smoothed_rps < scale_down_threshold and current_replicas > MIN_REPLICAS:
        # Find the right replica count
        for replicas in range(current_replicas - 1, MIN_REPLICAS - 1, -1):
            _, down_thresh = RPS_THRESHOLDS[replicas]
            if smoothed_rps >= down_thresh or replicas == MIN_REPLICAS:
                return replicas, f"RPS {smoothed_rps:.1f} < {scale_down_threshold:.1f} (scale-down threshold)"
        return MIN_REPLICAS, f"RPS {smoothed_rps:.1f} below minimum threshold"
    
    # Stay at current level
    return current_replicas, f"RPS {smoothed_rps:.1f} within stable range [{scale_down_threshold:.1f}, {scale_up_threshold:.1f})"


def should_scale(state: ServiceState, current_time: int, desired: int) -> Tuple[bool, str]:
    """
    Check if scaling is allowed (cooldown logic)
    
    Returns: (can_scale, reason)
    """
    if desired == state.current_replicas:
        return True, "No change needed"
    
    time_since_last_scale = current_time - state.last_scale_time
    
    if time_since_last_scale < COOLDOWN_PERIOD:
        return False, f"In cooldown (wait {COOLDOWN_PERIOD - time_since_last_scale}s)"
    
    return True, "Cooldown expired, scaling allowed"


# ==================== MAIN SIMULATION ====================
def main():
    print(f"[INFO] Loading dataset: {CSV_PATH}")
    df = pd.read_csv(CSV_PATH)
    
    # Validate columns
    required_cols = {"item", "timestamp", "request_rate"}
    missing = required_cols - set(df.columns)
    if missing:
        raise ValueError(f"Missing columns: {missing}")
    
    # Clean data
    df["timestamp"] = pd.to_numeric(df["timestamp"], errors="coerce")
    df["request_rate"] = pd.to_numeric(df["request_rate"], errors="coerce")
    df = df.dropna(subset=["timestamp", "request_rate"])
    
    # Create time buckets
    df["time_bucket"] = (df["timestamp"] // CONTROL_INTERVAL) * CONTROL_INTERVAL
    
    # Aggregate RPS per service per time bucket
    grouped = (
        df.groupby(["time_bucket", "item"], as_index=False)["request_rate"]
        .sum()
        .rename(columns={"request_rate": "total_rps"})
        .sort_values(["time_bucket", "item"])
        .reset_index(drop=True)
    )
    
    # Initialize service states
    service_states: Dict[str, ServiceState] = defaultdict(ServiceState)
    
    # Track events for output
    events = []
    
    # Statistics
    total_scales = 0
    upscales = 0
    downscales = 0
    cooldown_blocks = 0
    
    print("\n" + "="*120)
    print("ENHANCED REACTIVE AUTOSCALER SIMULATION".center(120))
    print("="*120)
    print(f"{'Time':<12} {'Service':<25} {'Raw RPS':<10} {'Smooth RPS':<12} {'Action':<12} {'Replicas':<10} {'Reason':<40}")
    print("-"*120)
    
    # Process each time bucket
    for _, row in grouped.iterrows():
        time_bucket = int(row["time_bucket"])
        service = row["item"]
        raw_rps = float(row["total_rps"])
        
        state = service_states[service]
        
        # Step 1: Update smoothed RPS
        smoothed_rps = update_smoothed_rps(state, raw_rps)
        
        # Step 2: Determine desired replicas (with hysteresis)
        desired, scaling_reason = desired_replicas_with_hysteresis(
            state.current_replicas, 
            smoothed_rps
        )
        
        # Step 3: Check cooldown
        can_scale, cooldown_reason = should_scale(state, time_bucket, desired)
        
        # Step 4: Make decision
        prev_replicas = state.current_replicas
        
        if desired > prev_replicas:
            if can_scale:
                action = "UPSCALE"
                state.current_replicas = desired
                state.last_scale_time = time_bucket
                total_scales += 1
                upscales += 1
                reason = scaling_reason
            else:
                action = "BLOCKED"
                cooldown_blocks += 1
                reason = cooldown_reason
        elif desired < prev_replicas:
            if can_scale:
                action = "DOWNSCALE"
                state.current_replicas = desired
                state.last_scale_time = time_bucket
                total_scales += 1
                downscales += 1
                reason = scaling_reason
            else:
                action = "BLOCKED"
                cooldown_blocks += 1
                reason = cooldown_reason
        else:
            action = "NO_CHANGE"
            reason = scaling_reason
        
        # Step 5: Log and record
        state.scale_history.append((time_bucket, state.current_replicas, smoothed_rps, reason))
        
        # Print decision
        replica_change = f"{prev_replicas} → {state.current_replicas}" if action in ["UPSCALE", "DOWNSCALE"] else f"{state.current_replicas}"
        print(f"{time_bucket:<12} {service:<25} {raw_rps:<10.2f} {smoothed_rps:<12.2f} {action:<12} {replica_change:<10} {reason:<40}")
        
        # Store event
        events.append({
            "time_bucket": time_bucket,
            "service": service,
            "raw_rps": raw_rps,
            "smoothed_rps": smoothed_rps,
            "prev_replicas": prev_replicas,
            "new_replicas": state.current_replicas,
            "action": action,
            "reason": reason
        })
    
    # Save results
    out_df = pd.DataFrame(events)
    out_df.to_csv(OUTPUT_CSV, index=False)
    
    # Print summary statistics
    print("\n" + "="*120)
    print("SIMULATION SUMMARY".center(120))
    print("="*120)
    print(f"Total events processed:    {len(events)}")
    print(f"Total scaling actions:     {total_scales}")
    print(f"  ↑ Upscales:              {upscales}")
    print(f"  ↓ Downscales:            {downscales}")
    print(f"  ⏸ Blocked by cooldown:   {cooldown_blocks}")
    print(f"Configuration:")
    print(f"  Cooldown period:         {COOLDOWN_PERIOD}s")
    print(f"  EMA alpha:               {EMA_ALPHA}")
    print(f"  Control interval:        {CONTROL_INTERVAL}s")
    
    print(f"\n[SUCCESS] Results saved to: {OUTPUT_CSV}")
    print("="*120)


if __name__ == "__main__":
    main()
"""
Live Reactive Autoscaler for Kubernetes
Works with any microservice architecture using Prometheus metrics

Architecture:
1. Reads real-time metrics from Prometheus
2. Makes scaling decisions using enhanced reactive logic
3. Executes scaling via Kubernetes API
4. Runs continuously as a control loop
"""
import os
import time
import logging
from typing import Dict, List, Optional
from dataclasses import dataclass, field
from datetime import datetime, timedelta
import requests
from kubernetes import client, config
from collections import defaultdict

# ==================== CONFIGURATION ====================
class AutoscalerConfig:
    """Central configuration for the autoscaler"""
    
    # Prometheus settings
    PROMETHEUS_URL =  os.getenv("PROMETHEUS_URL", "http://prometheus-server:9090") # Your Prometheus endpoint
    METRICS_QUERY_INTERVAL = 30  # Query metrics every 30 seconds
    
    # Kubernetes settings
    KUBERNETES_NAMESPACE = "default"  # Namespace to watch
    
    # Scaling parameters
    COOLDOWN_PERIOD = 60  # seconds between scaling actions
    EMA_ALPHA = 0.7  # Exponential moving average weight
    MIN_REPLICAS = 1
    MAX_REPLICAS = 10
    
    # RPS Thresholds with Hysteresis
    RPS_THRESHOLDS = {
        1: (10, 0),
        2: (30, 8),
        3: (60, 25),
        4: (100, 50),
        5: (float('inf'), 90)
    }
    
    # Metrics configuration
    RPS_METRIC_QUERY = 'sum(rate(http_requests_total{{service="{service}"}}[1m]))'
    
    # Logging
    LOG_LEVEL = logging.INFO


# ==================== DATA STRUCTURES ====================
@dataclass
class ServiceState:
    """Track state for each service"""
    service_name: str
    current_replicas: int = 1
    raw_rps: float = 0.0
    smoothed_rps: float = 0.0
    last_scale_time: float = 0.0
    scale_history: List[Dict] = field(default_factory=list)


# ==================== PROMETHEUS INTEGRATION ====================
class PrometheusClient:
    """Interface to Prometheus for metrics collection"""
    
    def __init__(self, url: str):
        self.url = url.rstrip('/')
        self.logger = logging.getLogger('PrometheusClient')
    
    def query(self, query: str) -> Optional[Dict]:
        """Execute a PromQL query"""
        try:
            response = requests.get(
                f"{self.url}/api/v1/query",
                params={'query': query},
                timeout=10
            )
            response.raise_for_status()
            data = response.json()
            
            if data['status'] == 'success':
                return data['data']
            else:
                self.logger.error(f"Query failed: {data}")
                return None
                
        except Exception as e:
            self.logger.error(f"Prometheus query error: {e}")
            return None
    
    def get_rps(self, service: str, query_template: str) -> Optional[float]:
        """Get current RPS for a service"""
        query = query_template.format(service=service)
        result = self.query(query)
        
        if result and result.get('result'):
            # Extract value from Prometheus response
            value = result['result'][0]['value'][1]
            return float(value)
        
        return None


# ==================== KUBERNETES INTEGRATION ====================
class KubernetesScaler:
    """Interface to Kubernetes API for scaling operations"""
    
    def __init__(self, namespace: str):
        self.namespace = namespace
        self.logger = logging.getLogger('KubernetesScaler')
        
        # Load kubernetes config
        try:
            config.load_incluster_config()  # For in-cluster deployment
            self.logger.info("Loaded in-cluster Kubernetes config")
        except:
            config.load_kube_config()  # For local development
            self.logger.info("Loaded local Kubernetes config")
        
        self.apps_v1 = client.AppsV1Api()
    
    def get_current_replicas(self, service: str) -> Optional[int]:
        """Get current replica count for a deployment"""
        try:
            deployment = self.apps_v1.read_namespaced_deployment(
                name=service,
                namespace=self.namespace
            )
            return deployment.spec.replicas
        except client.exceptions.ApiException as e:
            self.logger.error(f"Failed to get replicas for {service}: {e}")
            return None
    
    def scale_deployment(self, service: str, replicas: int) -> bool:
        """Scale a deployment to specified replica count"""
        try:
            # Read current deployment
            deployment = self.apps_v1.read_namespaced_deployment(
                name=service,
                namespace=self.namespace
            )
            
            # Update replica count
            deployment.spec.replicas = replicas
            
            # Patch the deployment
            self.apps_v1.patch_namespaced_deployment(
                name=service,
                namespace=self.namespace,
                body=deployment
            )
            
            self.logger.info(f"✅ Scaled {service} to {replicas} replicas")
            return True
            
        except client.exceptions.ApiException as e:
            self.logger.error(f"Failed to scale {service}: {e}")
            return False
    
    def list_deployments(self) -> List[str]:
        """List all deployments in namespace"""
        try:
            deployments = self.apps_v1.list_namespaced_deployment(
                namespace=self.namespace
            )
            return [d.metadata.name for d in deployments.items]
        except Exception as e:
            self.logger.error(f"Failed to list deployments: {e}")
            return []


# ==================== SCALING LOGIC ====================
class ReactiveScalingEngine:
    """Core scaling decision engine"""
    
    def __init__(self, config: AutoscalerConfig):
        self.config = config
        self.logger = logging.getLogger('ScalingEngine')
    
    def update_smoothed_rps(self, state: ServiceState, new_rps: float) -> float:
        """Calculate exponential moving average"""
        if state.smoothed_rps == 0.0:
            state.smoothed_rps = new_rps
        else:
            state.smoothed_rps = (
                self.config.EMA_ALPHA * new_rps + 
                (1 - self.config.EMA_ALPHA) * state.smoothed_rps
            )
        
        state.raw_rps = new_rps
        return state.smoothed_rps
    
    def desired_replicas(self, current_replicas: int, smoothed_rps: float) -> tuple[int, str]:
        """Determine desired replicas with hysteresis"""
        scale_up_threshold, scale_down_threshold = self.config.RPS_THRESHOLDS[current_replicas]
        
        # Check scale UP
        if smoothed_rps >= scale_up_threshold and current_replicas < self.config.MAX_REPLICAS:
            for replicas in range(current_replicas + 1, self.config.MAX_REPLICAS + 1):
                up_thresh, _ = self.config.RPS_THRESHOLDS[replicas]
                if smoothed_rps < up_thresh:
                    return replicas, f"Scale up: RPS {smoothed_rps:.1f} >= {scale_up_threshold:.1f}"
            return self.config.MAX_REPLICAS, f"Scale to max: RPS {smoothed_rps:.1f}"
        
        # Check scale DOWN
        elif smoothed_rps < scale_down_threshold and current_replicas > self.config.MIN_REPLICAS:
            for replicas in range(current_replicas - 1, self.config.MIN_REPLICAS - 1, -1):
                _, down_thresh = self.config.RPS_THRESHOLDS[replicas]
                if smoothed_rps >= down_thresh or replicas == self.config.MIN_REPLICAS:
                    return replicas, f"Scale down: RPS {smoothed_rps:.1f} < {scale_down_threshold:.1f}"
            return self.config.MIN_REPLICAS, f"Scale to min: RPS {smoothed_rps:.1f}"
        
        return current_replicas, f"Stable: RPS {smoothed_rps:.1f} in range"
    
    def should_scale(self, state: ServiceState, desired: int) -> tuple[bool, str]:
        """Check if scaling is allowed (cooldown logic)"""
        if desired == state.current_replicas:
            return True, "No change needed"
        
        current_time = time.time()
        time_since_last_scale = current_time - state.last_scale_time
        
        if time_since_last_scale < self.config.COOLDOWN_PERIOD:
            wait_time = int(self.config.COOLDOWN_PERIOD - time_since_last_scale)
            return False, f"Cooldown: wait {wait_time}s"
        
        return True, "Cooldown expired"


# ==================== MAIN AUTOSCALER ====================
class LiveReactiveAutoscaler:
    """Main autoscaler orchestrator"""
    
    def __init__(self, config: AutoscalerConfig):
        self.config = config
        self.logger = self._setup_logging()
        
        # Initialize components
        self.prometheus = PrometheusClient(config.PROMETHEUS_URL)
        self.k8s = KubernetesScaler(config.KUBERNETES_NAMESPACE)
        self.engine = ReactiveScalingEngine(config)
        
        # Service states
        self.service_states: Dict[str, ServiceState] = defaultdict(
            lambda: ServiceState(service_name="")
        )
        
        self.logger.info("🚀 Live Reactive Autoscaler initialized")
    
    def _setup_logging(self):
        """Configure logging"""
        logging.basicConfig(
            level=self.config.LOG_LEVEL,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        return logging.getLogger('Autoscaler')
    
    def control_loop_iteration(self):
        """Single iteration of the control loop"""
        # Get list of services to monitor
        services = self.k8s.list_deployments()
        
        if not services:
            self.logger.warning("No deployments found")
            return
        
        self.logger.info(f"Monitoring {len(services)} services: {services}")
        
        for service in services:
            try:
                self.process_service(service)
            except Exception as e:
                self.logger.error(f"Error processing {service}: {e}")
    
    def process_service(self, service: str):
        """Process scaling decision for a single service"""
        # Get current state
        state = self.service_states[service]
        state.service_name = service
        
        # Step 1: Get current RPS from Prometheus
        rps = self.prometheus.get_rps(service, self.config.RPS_METRIC_QUERY)
        if rps is None:
            self.logger.warning(f"No RPS data for {service}")
            return
        
        # Step 2: Update smoothed RPS
        smoothed_rps = self.engine.update_smoothed_rps(state, rps)
        
        # Step 3: Get current replicas from Kubernetes
        current_k8s_replicas = self.k8s.get_current_replicas(service)
        if current_k8s_replicas is None:
            return
        
        # Sync state with K8s reality
        state.current_replicas = current_k8s_replicas
        
        # Step 4: Determine desired replicas
        desired, reason = self.engine.desired_replicas(
            state.current_replicas,
            smoothed_rps
        )
        
        # Step 5: Check cooldown
        can_scale, cooldown_msg = self.engine.should_scale(state, desired)
        
        # Step 6: Make decision
        if desired != state.current_replicas:
            action = "UPSCALE" if desired > state.current_replicas else "DOWNSCALE"
            
            if can_scale:
                # Execute scaling
                success = self.k8s.scale_deployment(service, desired)
                
                if success:
                    state.current_replicas = desired
                    state.last_scale_time = time.time()
                    
                    log_msg = f"🔄 {action}: {service} {current_k8s_replicas}→{desired} | {reason}"
                    self.logger.info(log_msg)
                    
                    # Record in history
                    state.scale_history.append({
                        'timestamp': datetime.now().isoformat(),
                        'action': action,
                        'from': current_k8s_replicas,
                        'to': desired,
                        'rps': smoothed_rps,
                        'reason': reason
                    })
            else:
                self.logger.info(f"⏸️  BLOCKED: {service} | {cooldown_msg}")
        else:
            self.logger.debug(f"✓ NO_CHANGE: {service} @ {state.current_replicas} replicas | {reason}")
    
    def run(self):
        """Main control loop - runs forever"""
        self.logger.info("="*80)
        self.logger.info("Starting Live Reactive Autoscaler")
        self.logger.info(f"Namespace: {self.config.KUBERNETES_NAMESPACE}")
        self.logger.info(f"Prometheus: {self.config.PROMETHEUS_URL}")
        self.logger.info(f"Control interval: {self.config.METRICS_QUERY_INTERVAL}s")
        self.logger.info("="*80)
        
        while True:
            try:
                loop_start = time.time()
                
                # Run control loop
                self.control_loop_iteration()
                
                # Sleep until next interval
                elapsed = time.time() - loop_start
                sleep_time = max(0, self.config.METRICS_QUERY_INTERVAL - elapsed)
                
                if sleep_time > 0:
                    time.sleep(sleep_time)
                    
            except KeyboardInterrupt:
                self.logger.info("\n🛑 Shutting down autoscaler...")
                break
            except Exception as e:
                self.logger.error(f"Control loop error: {e}", exc_info=True)
                time.sleep(5)  # Brief pause before retry


# ==================== ENTRY POINT ====================
def main():
    """Start the live autoscaler"""
    config = AutoscalerConfig()
    autoscaler = LiveReactiveAutoscaler(config)
    autoscaler.run()


if __name__ == "__main__":
    main()
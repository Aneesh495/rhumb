module matcher

import math

// Default Gaussian standard deviation for GPS positioning accuracy (4.07 meters per Newson-Krumm 2009).
pub const default_sigma_z = 4.07

// Default exponential decay factor beta for road network vs Euclidean distance discrepancy.
pub const default_beta = 3.0

// emission_log_probability calculates the log-likelihood of observing GPS error distance given standard deviation sigma.
pub fn emission_log_probability(distance_m f64, sigma_z f64) f64 {
	log_norm := -math.log(math.sqrt(2.0 * math.pi) * sigma_z)
	exp_term := -(distance_m * distance_m) / (2.0 * sigma_z * sigma_z)
	return log_norm + exp_term
}

// transition_log_probability evaluates the log-likelihood of transitioning between two candidate road states.
// Penalizes absolute discrepancy |great_circle_dist - network_dist| via exponential distribution.
pub fn transition_log_probability(euclidean_dist_m f64, network_dist_m f64, beta f64) f64 {
	delta_d := math.abs(euclidean_dist_m - network_dist_m)
	log_beta := -math.log(beta)
	exp_term := -delta_d / beta
	return log_beta + exp_term
}

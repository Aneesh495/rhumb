module app

// ANSI color escape codes for high-contrast dark-mode terminal rendering.
pub const color_reset = '\x1b[0m'
pub const color_bold = '\x1b[1m'
pub const color_dim = '\x1b[2m'
pub const color_blue = '\x1b[38;5;39m'
pub const color_cyan = '\x1b[38;5;51m'
pub const color_green = '\x1b[38;5;82m'
pub const color_yellow = '\x1b[38;5;220m'
pub const color_red = '\x1b[38;5;196m'
pub const color_gray = '\x1b[38;5;245m'

// banner prints the stylized ASCII header for Rhumb.
pub fn banner() {
	println('${color_cyan}${color_bold}')
	println('  ____  _   _ _   _ __  __ ____  ')
	println(' |  _ \\| | | | | | |  \\/  | __ ) ')
	println(' | |_) | |_| | | | | |\\/| |  _ \\ ')
	println(' |  _ <|  _  | |_| | |  | | |_) |')
	println(' |_| \\_\\_| |_|\\___/|_|  |_|____/ ')
	println('${color_reset}${color_gray} High-Performance Geospatial Routing & Map-Matching Engine${color_reset}')
	println('')
}

// print_success prints a green success indicator.
pub fn print_success(msg string) {
	println('${color_green}[✓]${color_reset} ${msg}')
}

// print_info prints a blue informational indicator.
pub fn print_info(msg string) {
	println('${color_blue}[i]${color_reset} ${msg}')
}

// print_warn prints a yellow warning indicator.
pub fn print_warn(msg string) {
	println('${color_yellow}[!]${color_reset} ${msg}')
}

// print_error prints a red error indicator.
pub fn print_error(msg string) {
	println('${color_red}[x]${color_reset} ${msg}')
}

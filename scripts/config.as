// config.as

// Ensure this file is only loaded once
if (!_global.__CONFIG_INCLUDED__) {
    _global.__CONFIG_INCLUDED__ = true;

    // Define a global register bank
    _global.Config = {
        // Use an object to store registers dynamically
        registers: {},
        arguments: []
    };
}

// Define a macro to add two numbers
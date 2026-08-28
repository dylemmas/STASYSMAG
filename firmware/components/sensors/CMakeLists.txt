idf_component_register(
    SRCS "sensor_hal.cpp"
    INCLUDE_DIRS "."
    REQUIRES driver esp_adc system_config
)

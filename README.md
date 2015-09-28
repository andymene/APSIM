A package containing general purpose utility functions for loading and manipulating APSIM output and met files.

Release Notes
=============

### 0.8.2

-   loadMet will now read existing constants.
-   metFile class has had a slot for constants added. Constants are a character vector of the format: variable=value.
-   prepareMet now correctly handles R Date formatted dates.

### 0.8.1

-   Fix for reading simulator output processed on a Condor cluster.

### 0.8.0

-   Initial Release.

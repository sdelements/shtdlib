# shtdlib
Shell Standard Library

## Compatibility

Supported bash versions currently include the following though not all
functions will be supported on all versions.

- 3.1.23
- 3.2.57
- 4.0.44
- 4.1.17
- 4.2.53
- 4.3.48
- 4.4.23
- 5.0-beta


## Installation

For an example of how to install/import see:

```bash
import_install_example.sh
```

## Testing

For testing bash code across multiple versions of bash we highly recommend
using the bashtester submodule, you can pull it with this repository by using:

```bash
git clone --recurse-submodules https://github.com/sdelements/shtdlib.git
```

Or if you've already cloned this project you can initialize and pull using:

```bash
git submodule init
git submodule update --recursive
```

### Test Examples:

- all supported versions (using docker containers)

    ```bash
    source shtdlib.sh && test_shtdlib
    ```

- local bash only, no containers
    ```bash
    source shtdlib.sh && test_shtdlib local
    ```

- specific bash version(s) and/or local
    ```bash
    source shtdlib.sh && test_shtdlib 3.1.23 4.4.23 local
    ```

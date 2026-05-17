# gdal-mdim-summary

A one-file `jq` script that turns the JSON output of `gdal mdim info` into a
human-readable summary, inspired by xarray's `Dataset` repr but driven by
GDAL's own structural metadata: dimension types, indexing variables, group
hierarchy, packing.

Use it for quick exploration of multidimensional files — netCDF, HDF5, Zarr,
or anything else GDAL's multidim drivers can read — including remote files
over `/vsicurl/`.

## Quick start

```sh
# one-time install: drop the script anywhere on disk
curl -fsSL https://raw.githubusercontent.com/mdsumner/gdal-mdim-summary/main/mdim-summary.jq \
  -o ~/.local/bin/mdim-summary.jq

# use it
gdal mdim info file.nc | jq -rf ~/.local/bin/mdim-summary.jq
```

Or a shell alias / function for less typing:

```sh
# in ~/.bashrc or ~/.zshrc
mdim-summary() { gdal mdim info "$@" | jq -rf ~/.local/bin/mdim-summary.jq; }

# then
mdim-summary file.nc
mdim-summary /vsicurl/https://example.org/data.nc
```

## Requirements

- **GDAL 3.10+** for the unified `gdal mdim info` command. Older GDAL
  versions with `gdalmdiminfo` produce the same JSON shape, so
  `gdalmdiminfo file.nc | jq -rf mdim-summary.jq` also works.
- **jq 1.6+** (any reasonably current `jq` will do).

## What it shows

Four blocks, conditionally emitted:

- **Dimensions** — flat list with size and GDAL dimension type
  (`HORIZONTAL_X`, `VERTICAL DOWN`, `TEMPORAL`, …) when known.
- **Coordinates (indexing variables)** — arrays that are dimension
  indexing variables per GDAL's model (not name-matched).
- **Data variables** — grouped by dimension signature, with shape on
  the signature header and chunking inline on each array.
- **Groups** — nested group paths, when the file has non-trivial nesting.

Plus a root-level attribute count.

## Examples

### BRAN2023 ocean model (netCDF, indexed coords, remote)

```sh
gdal mdim info /vsicurl/https://thredds.nci.org.au/thredds/fileServer/gb6/BRAN/BRAN2023/daily/ocean_temp_2010_01.nc \
  | jq -rf mdim-summary.jq
```

```
<gdal.mdim: /> (netCDF/NETCDF4)

Dimensions:
  /xt_ocean        3600  HORIZONTAL_X
  /yt_ocean        1500  HORIZONTAL_Y
  /st_ocean        51    VERTICAL DOWN
  /Time            31    TEMPORAL
  /nv              2
  /st_edges_ocean  52    VERTICAL DOWN

Coordinates (indexing variables):
  * /xt_ocean        (xt_ocean)        Float64  degrees_E
  * /yt_ocean        (yt_ocean)        Float64  degrees_N
  * /st_ocean        (st_ocean)        Float64  meters
  * /Time            (Time)            Float64  days since 1979-01-01 00:00:00
  * /nv              (nv)              Float64  none
  * /st_edges_ocean  (st_edges_ocean)  Float64  meters

Data variables:
  (Time [31]):
    /average_T1  Float64  days since 1979-01-01 00:00:00  chunks=[1]
    /average_T2  Float64  days since 1979-01-01 00:00:00  chunks=[1]
    /average_DT  Float64  days                            chunks=[1]
  (Time, nv [31,2]):
    /Time_bnds   Float64  days                            chunks=[1,2]
  (Time, st_ocean, yt_ocean, xt_ocean [31,51,1500,3600]):
    /temp        Int16    degrees C  [packed: scale=0.0077822 offset=245]  chunks=[1,1,300,300]

Attributes (9): filename, NumFilesInSet, grid_type, NCO, history, …
```

The `(Time, st_ocean, yt_ocean, xt_ocean [31,51,1500,3600])` line tells you
both the shape of the grid and that `temp` is its only inhabitant; the
`chunks=[1,1,300,300]` annotation says how it's stored.

### WAOM ROMS grid (netCDF, staggered Arakawa C-grid)

ROMS files have no dimension indexing variables — coordinates live as 2D
`lat_rho`/`lon_rho` arrays on each stagger. The dim-signature grouping
makes the Arakawa C-grid structure (centres, faces, corners) visible at
a glance:

```
<gdal.mdim: /> (netCDF/64BIT_OFFSET)

Dimensions:
  /xi_rho   3150
  /xi_u     3149
  /xi_v     3150
  /xi_psi   3149
  /eta_rho  2650
  /eta_u    2650
  /eta_v    2649
  /eta_psi  2649
  /bath     0

Data variables:
  (eta_psi, xi_psi [2649,3149]):
    /x_psi     Float64  meter
    /y_psi     Float64  meter
    /lon_psi   Float64  degree_east
    /lat_psi   Float64  degree_north
    /mask_psi  Float64
  (eta_rho, xi_rho [2650,3150]):
    /angle     Float64  radians
    /pm        Float64  meter-1
    /pn        Float64  meter-1
    /dndx      Float64  meter
    /dmde      Float64  meter
    /f         Float64  second-1
    /h         Float64  meter
    /zice      Float64  meter
    /x_rho     Float64  meter
    /y_rho     Float64  meter
    /lon_rho   Float64  degree_east
    /lat_rho   Float64  degree_north
    /mask_rho  Float64
  (eta_u, xi_u [2650,3149]):
    /x_u       Float64  meter
    /y_u       Float64  meter
    /lon_u     Float64  degree_east
    /lat_u     Float64  degree_north
    /mask_u    Float64
  (eta_v, xi_v [2649,3150]):
    /x_v       Float64  meter
    /y_v       Float64  meter
    /lon_v     Float64  degree_east
    /lat_v     Float64  degree_north
    /mask_v    Float64
  (bath, eta_rho, xi_rho [0,2650,3150]):
    /hraw      Float64  meter

Attributes (2): type, history
```

`xi_rho` and `xi_v` both have size 3150 but are semantically distinct;
signature grouping (on dim name, not size) keeps them separate. The
`bath` dim has size 0, making `hraw` empty — visible in the shape
annotation `[0,2650,3150]`.

### HDFEOS swath (HDF5, nested groups)

```
<gdal.mdim: /> (HDF5)

Dimensions:
  /HDFEOS/SWATHS/MySwath/Band        20
  /HDFEOS/SWATHS/MySwath/AlongTrack  30
  /HDFEOS/SWATHS/MySwath/CrossTrack  40

Data variables:
  (AlongTrack, CrossTrack [30,40]):
    /HDFEOS/SWATHS/MySwath/Geolocation Fields/Latitude   Float32
    /HDFEOS/SWATHS/MySwath/Geolocation Fields/Longitude  Float32
  (Band, AlongTrack, CrossTrack [20,30,40]):
    /HDFEOS/SWATHS/MySwath/Data Fields/MyDataField       Float32  chunks=[3,4,6]

Scalars:
  /HDFEOS INFORMATION/StructMetadata.0                   String

Groups (8):
  /HDFEOS
  /HDFEOS/ADDITIONAL
  /HDFEOS/ADDITIONAL/FILE_ATTRIBUTES
  /HDFEOS/SWATHS
  /HDFEOS/SWATHS/MySwath
  /HDFEOS/SWATHS/MySwath/Data Fields
  /HDFEOS/SWATHS/MySwath/Geolocation Fields
  /HDFEOS INFORMATION
```

## How it compares

- **`ncdump -h`** lists variables in declaration order, with no dim-signature
  grouping and no coord/data distinction. On a multi-grid file like WAOM, the
  staggered structure is invisible.
- **xarray's repr** uses name-matching to identify coordinates and has no
  first-class group concept. It's heuristic where this script is structural —
  GDAL's `indexing_variable` field is the source of truth.
- **`h5dump`** shows raw HDF5 hierarchy but no semantic structure (and
  doesn't work on netCDF-3 or Zarr).

This script is a thin presentation layer over `gdal mdim info`. The JSON
remains the contract; this is just a way to read it.

## Limitations and notes

- **Group-scoped namespacing.** Dim names in signatures (`(Time, st_ocean)`)
  are bare. If two groups define same-named dims, this can be ambiguous —
  the full path is always available on array names to disambiguate, but a
  future version may switch to full paths in signatures when ambiguity is
  detected.
- **Attribute display is shallow.** Only root-level attributes are summarised,
  truncated to the first five names. Per-array attributes are not shown —
  use `gdal mdim info` directly for the full dump.
- **Scale precision.** Packing parameters are shown as GDAL emits them,
  which can be long (e.g. `scale=0.0077822199091315269`). Cosmetic; not
  yet truncated.
- **No filtering.** Every array is shown. For files with hundreds of
  variables, that's a wall of text. A future flag could filter by dim,
  group, or pattern.

## Future direction

This script is essentially a prototype of what could become a built-in
`--format=text` mode for `gdal mdim info`, or a `gdal mdim summary`
subcommand. The layout uses only metadata GDAL already exposes; the
formatting is the entire contribution.

If you find it useful and have thoughts on what a richer built-in
version should do, the issues tab on this repo is a good place to
collect them. A formal GDAL feature request will likely follow once
the layout has been exercised on enough real files.

## License

MIT. See `LICENSE`.

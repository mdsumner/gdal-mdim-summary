# mdim-summary.jq — human-readable summary of `gdal mdim info` JSON
#
# Usage:
#   gdal mdim info FILE | jq -rf mdim-summary.jq
#
# Produces a layout inspired by xarray's repr, organised around four blocks:
#   Dimensions    — flat list, with size and GDAL dimension type/direction
#   Coordinates   — arrays that are dimension indexing variables (per GDAL)
#   Data variables — grouped by dimension signature, with shape and chunks
#   Groups        — nested group structure, when present
#
# Requires:
#   - GDAL 3.10+ (the unified `gdal` CLI; `gdalmdiminfo` JSON works too)
#   - jq 1.6+
#
# https://github.com/mdsumner/gdal-mdim-summary

def pad(w): . as $s | $s + (if (w - ($s | length)) > 0 then " " * (w - ($s | length)) else "" end);

def fmt_value:
  .datatype
  + (if (.unit // "") != "" then "  " + .unit else "" end)
  + (if .scale or .offset then "  [packed: scale=\(.scale // 1) offset=\(.offset // 0)]" else "" end);

def aligned(indent):
  . as $rows
  | if ($rows | length) == 0 then empty
    else
      (transpose | map(map(length) | max)) as $widths
      | $rows
      | map(. as $row | [range(0; $row | length) as $i | $row[$i] | pad($widths[$i])] | join("  ") | indent + .)
      | .[]
    end;

# Walk every group, yielding {path, group}. Root path is "/".
def walk_groups($prefix):
  {path: $prefix, group: .},
  ( (.groups // {}) | to_entries[]
    | .key as $k
    | (.value | walk_groups($prefix + (if $prefix == "/" then "" else "/" end) + $k))
  );

. as $root
| [$root | walk_groups("/")] as $all_groups

# All arrays across all groups
| [$all_groups[] | .path as $gp | (.group.arrays // {}) | to_entries[]
   | {
       full_name: (if $gp == "/" then "/" + .key else $gp + "/" + .key end),
       name: .key,
       group_path: $gp,
       value: .value
     }
  ] as $arrays

# All dimensions across all groups
| [$all_groups[] | .path as $gp | (.group.dimensions // [])[]
   | {full_name: .full_name, group_path: $gp, dim: .}
  ] as $dims

# Set of dim paths that have an indexing_variable
| [$dims[] | select(.dim.indexing_variable) | .full_name] as $coord_dim_paths

# Coords: single-dim, dim is indexed, bare names match
| [$arrays[]
   | select(
       (.value.dimensions | length) == 1
       and ([.value.dimensions[0]] | inside($coord_dim_paths))
       and ((.value.dimensions[0] | split("/") | last) == .name)
     )
  ] as $coords

| ([$coords[] | .full_name]) as $coord_names

| [$arrays[] | select([.full_name] | inside($coord_names) | not) | select((.value.dimensions // []) | length > 0)] as $data_vars
| [$arrays[] | select([.full_name] | inside($coord_names) | not) | select((.value.dimensions // []) | length == 0)] as $scalars

# --- emit ---
| (
    "<gdal.mdim: \($root.name // "?")> (\($root.driver // "?")"
    + (if $root.structural_info.NC_FORMAT then "/" + $root.structural_info.NC_FORMAT else "" end)
    + ")"
  ),
  "",

  (if ($dims | length) > 0 then
    "Dimensions:",
    ([$dims[] | [.full_name, (.dim.size | tostring),
                  ((.dim.type // "") + (if .dim.direction then " " + .dim.direction else "" end))]]
     | aligned("  ")),
    ""
   else empty end),

  (if ($coords | length) > 0 then
    "Coordinates (indexing variables):",
    ([$coords[] | ["* " + .full_name,
                   "(" + (.value.dimensions | map(split("/") | last) | join(", ")) + ")",
                   (.value | fmt_value)]]
     | aligned("  ")),
    ""
   else empty end),

  (if ($data_vars | length) > 0 then
    "Data variables:",
    (
      $data_vars
      | group_by(.value.dimensions // [])
      | sort_by(.[0].value.dimensions // [] | length)
      | .[]
      | (
          "  ("
          + (.[0].value.dimensions // [] | map(split("/") | last) | join(", "))
          + " ["
          + (.[0].value.dimension_size // [] | map(tostring) | join(","))
          + "]):"
        ),
        ([.[] | [
            .full_name,
            (.value | fmt_value),
            (if .value.block_size then "chunks=[" + (.value.block_size | map(tostring) | join(",")) + "]" else "" end)
          ]] | aligned("    "))
    ),
    ""
   else empty end),

  (if ($scalars | length) > 0 then
    "Scalars:",
    ([$scalars[] | [.full_name, (.value | fmt_value)]] | aligned("  ")),
    ""
   else empty end),

  ($all_groups | length as $ng
   | if $ng > 1 then
       "Groups (\($ng - 1)):",
       ($all_groups | map(select(.path != "/") | "  " + .path) | .[]),
       ""
     else empty end),

  (
    ($root.attributes // {}) | to_entries as $atts
    | ($atts | length) as $natt
    | if $natt > 0 then
        "Attributes (\($natt)): "
        + ($atts | map(.key) | .[0:5] | join(", "))
        + (if $natt > 5 then ", …" else "" end)
      else empty end
  )

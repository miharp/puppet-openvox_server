# @summary Renders a value as a HOCON literal
#
# Strings are quoted, with backslashes and double quotes escaped; numbers
# and booleans are bare; arrays are rendered element by element.
#
# @param value
#   The value to render.
# @return [String] The HOCON literal.
function openvox_server::hocon_value(
  Variant[String, Numeric, Boolean, Array[Variant[String, Numeric, Boolean]]] $value,
) >> String {
  $value ? {
    String  => "\"${value.regsubst(/\\/, '\\\\\\\\', 'G').regsubst(/"/, '\\"', 'G')}\"",
    Array   => "[${value.map |$element| { openvox_server::hocon_value($element) }.join(', ')}]",
    default => "${value}", # lint:ignore:only_variable_string String() pads floats (1.500000)
  }
}

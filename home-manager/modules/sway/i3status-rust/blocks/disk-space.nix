{ ... }:

{
  block = "disk_space";
  info_type = "available";
  alert_unit = "GB";
  alert = 10.0;
  warning = 15.0;
  format = " $icon $available ";
  format_alt = " $icon $available / $total ";
}

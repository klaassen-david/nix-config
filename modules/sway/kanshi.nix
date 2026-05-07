{ pkgs, ... }: {
  services.kanshi = {
    enable = true;
    systemdTarget = "sway-session.target";
    profiles = {

      hermes-work = {
        outputs = [
          {
            criteria = "BOE 0x0BC9 Unknown";
            position = "0,360";
            status = "enable";
          }
          {
            criteria = "LG Electronics 24MB37 607NTNHC8631";  
            mode = "1920x1080";
            position = "2560,360";
            status = "enable";
          }
          {
            criteria = "ASUSTek COMPUTER INC ASUS VA27A S9LMTF073523";
            mode = "2560x1440";
            position = "4480,0";
            status = "enable";
          }
        ];
      };

    };
  };
}

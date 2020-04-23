module "xiaoqiang.XQFeatures"


FEATURES = {
    ["system"] = {
        ["shutdown"] = "0",
        ["downloadlogs"] = "0",
        ["i18n"] = "1",
        ["infileupload"] = "1",        
        ["task"] = "0"
    },
    ["wifi"] = {
        ["wifi24"] = "1",
        ["wifi50"] = "0",
        ["wifiguest"] = "0",
        ["wifimerge"] = "1"
    },
    ["apmode"] = {
        ["wifiapmode"] = "1",
        ["lanapmode"] = "1"
    },
    ["netmode"] = {
        ["elink"] = "0"
    },
    ["apps"] = {
        ["apptc"] = "0",
        ["qos"] = "1"
    },
    ["hardware"] = {
        ["usb"] = "0",
        ["disk"] = "0"
    }
}

module("luci.controller.diagnosis.index", package.seeall)
function index()
    local root = node()
    if not root.target then
        root.target = alias("diagnosis")
        root.index = true
    end
    local page   = node("diagnosis")
    page.target  = firstchild()
    page.title   = _("")
    page.order   = 110
    page.sysauth = "admin"
    page.mediaurlbase = "/xiaoqiang/diagnosis"
    page.sysauth_authenticator = "htmlauth"
    page.index = true
    entry({"diagnosis"}, template("diagnosis/home"), _("首页"), 1, 0x09)
end
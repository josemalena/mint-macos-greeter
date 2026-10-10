icon_files = [
    'a11y.svg',
    'active.png',
    'arrow_left.svg',
    'arrow_right.svg',
    'battery.svg',
    'battery_10.svg',
    'battery_25.svg',
    'battery_50.svg',
    'dialog_close.svg',
    'dialog_close_highlight.svg',
    'dialog_close_press.svg',
    'hibernate_highlight.svg',
    'hibernate.svg',
    'keyboard.svg',
    'message.png',
    'remote_login_help.png',
    'restart_highlight.svg',
    'restart.svg',
    'shadow.png',
    'shutdown_highlight.svg',
    'shutdown_dialog.svg',
    'shutdown.svg',
    'suspend_highlight.svg',
    'suspend.svg',
    'switcher_corner.png',
    'switcher_left.png',
    'switcher_top.png',
]

install_data(
    icon_files,
    install_dir: pkgdatadir,
)

# El esquema GSettings es el del slick-greeter de Mint (ya instalado): este
# fork lo comparte y no lo instala. Tampoco los man.
install_data(
    'slick-greeter-mac.desktop',
    install_dir: datadir / 'xgreeters',
)

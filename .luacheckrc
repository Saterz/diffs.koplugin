std = "luajit"
max_line_length = 120

globals = {
    "G_reader_settings",
}

files["spec/*"].std = "+busted"

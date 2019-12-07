# warning

warning is a command-line macOS program to show a customizable border around the screen.
It is intended to be used by other scripts to visually grab the user's attention.

## Configuring the border

The border is drawn in red with a width of 10 pixels by default. To change this, send commands to the app
using the UNIX domain socket `/tmp/warning`:

```
$ echo "width 100" | nc -U /tmp/warning # set the border width to 100 pixels
$ echo "color 0000ff99" | nc -U /tmp/warning # set the border color to a semi-transparent blue
```

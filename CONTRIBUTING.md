# Contributing to rv51


## Boundaries and expectations

[rv51][rv51] is a personal project of [@cyrozap][cyrozap]. This means that
[@cyrozap][cyrozap] works on this project for fun, in his free time, on his own
schedule, and in the direction he chooses. To this end, [@cyrozap][cyrozap]
reserves the right to ignore or reject issues, pull requests, and requests for
support, for any reason or no reason at all.

rv51 is also a [Free Software][free-software] project. That means anyone can use
rv51 for any purpose, can study and modify it, redistribute it, and distribute
modified copies of it. So if you'd like to use rv51 for some particular purpose,
would like to change it to meet some need of yours, or simply want to share it
with others, so long as you follow the terms of the [license][license] you have
every right to do so. You don't need any extra permission to make changes in
your own fork of the project, whether that fork exists only privately on your
computer or if it has been posted publicly on the internet.

That said, if you intend for your changes to be included in [@cyrozap's fork of
rv51][rv51], please open an issue to ask if those changes would be merged
_before_ you perform any work. If you don't ask first and just open a pull
request once you've finished your work, there's a good chance that the pull
request will be rejected. As rv51 is an assembly-language project, it's critical
for the maintenance of the project that the code style and design/architecture
be kept consistent. Since every new feature will have some impact on code size
or performance, and "simply" making features configurable makes testing much
more difficult (every new feature flag doubles the number of possible feature
combinations), new features (like the C extension, M mode, and performance
counters) and their designs must be considered carefully _before_ they are
implemented. It's for this reason that you're asked to open an issue first if
you have an idea for a change--this way, the design and tradeoffs can be
discussed before any work is done, reducing the likelihood of the change being
rejected.


## Contribution process

1. Search through both [open and closed issues][all-issues] to make sure that
   what you're about to ask hasn't already been asked about.
2. [Open an issue][new-issue] in this repository explaining the kind of change
   you would like to make.
3. [@cyrozap][cyrozap] will inform you in the issue of any next steps to take.


## Code design guidelines

- Follow the "Rules and conventions" in [main.S][main] unless it's necessary to
  break them.
  - If a rule/convention needs to be broken, note it in a comment near the
    relevant code.
- If you need internal memory for this feature, use the [register mapping
  spreadsheet][regmap] to help plan the allocation.
  - Take memory from the stack space first, unless the memory will need some
    special kind of access (e.g., for direct access to bits).
- Avoid pushing data to the stack except where necessary (e.g., to temporarily
  save `DPTR` before loading the address of a jump table).
- Comment your code extensively, as if you'll wake up one day having no memory
  of ever having written that code.
  - Explain what registers are being used for what variables, why you're making
    the calculations you're making--those kinds of things.
  - See the existing comments in the code to get a better idea of what code
    should or should not have comments.


[rv51]: https://github.com/cyrozap/rv51
[cyrozap]: https://github.com/cyrozap
[free-software]: https://www.gnu.org/philosophy/free-sw.html
[license]: COPYING.txt
[all-issues]: https://github.com/cyrozap/rv51/issues?q=is%3Aissue
[new-issue]: https://github.com/cyrozap/rv51/issues/new
[main]: src/main.S
[regmap]: doc/Register-Mapping.ods

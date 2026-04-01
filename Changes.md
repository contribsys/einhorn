# 1.1.0

- Make the `fiddle` gem dependency optional.
  This gem is only necessary if you use the `-k` flag and since
  it is native, requires libffi and a compiler to be installed.
  Add `gem "fiddle"` to your Gemfile to use the `-k` flag.

# 1.0.1

- Add `fiddle` to gemspec dependencies [#111]
— Minor formatting and removing dead code

# 1.0.0

- Use `YAML.safe_load` for compatibility with Ruby 3.1+ [#102]
- Functionality previously commented or logged as deprecated has been removed.
- Standardize code formatting with `standard`
- Add GitHub CI with Ruby version matrix
- Drop support for Rubies below 2.5.

Einhorn is now owned and actively maintained by Mike Perham of Contributed Systems.
Thank you to the Stripe developers who wrote Einhorn and maintained it to this point.

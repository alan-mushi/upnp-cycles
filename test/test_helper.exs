##
# The :network tag is used to identify which tests do suspicious stuff on the network :)
##
ExUnit.configure(exclude: [network: true])

Application.ensure_all_started(:shodan)

ExUnit.start()

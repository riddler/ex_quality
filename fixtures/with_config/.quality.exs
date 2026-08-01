# Custom quality configuration for testing
[
  credo: [
    strict: false,
    enabled: true
  ],
  dialyzer: [
    enabled: false
  ],
  custom: [
    # A command stage printing the JSON finding contract.
    [
      key: :house_rules,
      name: "House rules",
      command: "echo",
      args: [~s({"summary": "No bare Logger calls", "findings": []})]
    ],
    # A command stage that says it is not applicable rather than failing.
    [
      key: :prerequisite,
      name: "Prerequisite",
      command: "sh",
      args: ["-c", "echo 'nothing to check here'; exit 2"],
      skip_exit_code: 2
    ]
  ]
]

module.exports = {
  defaultBrowser: "Firefox",
  options: {
    checkForUpdate: false
  },
  handlers: [
    {
      match: ({ opener }) =>
        ["Slack"].includes(opener.name),
      browser: ({ urlString }) => ({
        name: "Firefox",
        args: ["-P", "work", urlString],
      }),
    },
  ]
}

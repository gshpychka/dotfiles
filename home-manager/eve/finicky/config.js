module.exports = {
  defaultBrowser: ({ urlString }) => ({
    name: "Firefox",
    args: ["-P", "personal", urlString],
  }), 
  options: {
    checkForUpdate: false
  },
  handlers: [
    {
      match: ({ opener, url }) => {
        const basedOnOpener =  [
          "Slack",
          "Leapp"
        ].some(
          appName => opener.path.toLowerCase().includes(
            appName.toLowerCase()
          )
        );
        const basedOnUrl = [
          "aws.amazon.com",
          "github.com",
        ].some(
          targetHostName => url.host.toLowerCase().includes(
            targetHostName.toLowerCase()
          )
        );
        finicky.log('Opening in work profile');
        return basedOnOpener || basedOnUrl;
      },
      browser: ({ urlString }) => ({
        name: "Firefox",
        args: ["-P", "work", urlString],
      }),
    },
  ]
}

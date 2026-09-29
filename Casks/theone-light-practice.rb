cask "theone-light-practice" do
  version "1.0.0"
  sha256 "c439e6114e297c05ef1047edd44566b604f6234ae9d5f7e03f9234f925b55fbe"

  url "https://github.com/Shmoopi/TheONE-Light-Practice/releases/download/v#{version}/TheONE.Light.Practice.dmg",
      verified: "github.com/Shmoopi/TheONE-Light-Practice/"
  name "TheONE Light Practice"
  desc "Learn any song on a THE ONE Light light-up keyboard"
  homepage "https://github.com/Shmoopi/TheONE-Light-Practice"

  depends_on macos: ">= :sonoma"

  app "TheONE Light Practice.app"

  zap trash: [
    "~/Library/Application Support/TheONE Light Practice",
  ]
end

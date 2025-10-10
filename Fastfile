lane :build_launcher do
  gym(
    workspace: "bybylaucherjava.xcworkspace",
    scheme: "bybylaucherjava",
    clean: true,
    export_method: "development", # or ad-hoc (không quan trọng nếu không 
ký)
    skip_codesigning: true,
    export_options: {
      compileBitcode: false,
      signingStyle: "manual",
      sign: false
    },
    output_name: "bybylaucherjava.ipa",
    output_directory: "build"
  )
end


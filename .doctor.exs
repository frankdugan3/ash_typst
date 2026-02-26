%Doctor.Config{
  ignore_modules: [
    AshTypst.NIF,
    ~r/AshTypst\.Resource\.Errors\./,
    ~r/AshTypst\.Resource\.Render\./,
    ~r/AshTypst\.Resource\.Transformers\./,
    ~r/AshTypst\.Resource\.Verifiers\./,
    AshTypst.Resource.Render,
    AshTypst.Resource.Template,
    AshTypst.Resource.Info
  ],
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 100,
  min_overall_doc_coverage: 50,
  min_overall_spec_coverage: 50
}

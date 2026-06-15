%Doctor.Config{
  ignore_modules: [
    AshTypst.NIF,
    AshTypst.Code,
    ~r/AshTypst\.Resource\.Errors\./,
    ~r/AshTypst\.Resource\.Render\./,
    ~r/AshTypst\.Resource\.Transformers\./,
    ~r/AshTypst\.Resource\.Verifiers\./,
    AshTypst.Resource.Render,
    AshTypst.Resource.Template,
    AshTypst.Resource.Info
  ],
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 0,
  min_overall_doc_coverage: 50,
  min_overall_spec_coverage: 0,
  struct_type_spec_required: false
}

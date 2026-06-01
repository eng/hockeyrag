import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["field", "form"]

  fill(event) {
    const text = event.currentTarget.textContent.trim()
    this.fieldTarget.value = text
    this.formTarget.requestSubmit()
  }
}

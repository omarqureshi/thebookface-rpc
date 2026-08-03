# frozen_string_literal: true

# Reactions. The Rails action returned a Turbo Stream that swapped the bar;
# here toggle returns data and React repaints, so the steps click and then wait
# on the rendered count.

When("I react {string} to the post") do |emoji|
  within("[data-testid='reactions-post']") { click_button "React #{emoji}" }
end

When("I react {string} to the comment {string}") do |emoji, text|
  within(comment_card(text)) { click_button "React #{emoji}" }
end

# Toggling the same emoji off removes the reaction entirely — the count cache
# drops to nothing rather than to zero, so the bar shows no numbers at all.
Then("the post has no reaction counts") do
  within("[data-testid='reactions-post']") do
    expect(page).to have_no_css(".reactions__count")
  end
end

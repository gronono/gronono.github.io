package fr.parlonscode.sqlinjection;

import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.Id;

import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.ToString;

@Entity
@Getter
@NoArgsConstructor
@ToString
public class Person {

	@Id
	@GeneratedValue
	private Long id;
	
	private String name;

	public Person(String name) {
		this.name = name;
	}
}
